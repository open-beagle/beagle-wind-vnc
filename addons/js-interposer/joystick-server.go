package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/veandco/go-sdl2/sdl"
)

const (
	LOG_FILE                  = "/tmp/selkies_js_go.log"
	ABS_MIN                   = -32767
	ABS_MAX                   = 32767
	DPAD_UP                   = 12
	DPAD_DOWN                 = 13
	DPAD_LEFT                 = 14
	DPAD_RIGHT                = 15
	L2_BUTTON                 = 6
	R2_BUTTON                 = 7
	JS_EVENT_BUTTON           = 0x01
	JS_EVENT_AXIS             = 0x02
	BTN_A                     = 0x130
	BTN_B                     = 0x131
	BTN_X                     = 0x133
	BTN_Y                     = 0x134
	BTN_TL                    = 0x136
	BTN_TR                    = 0x137
	BTN_SELECT                = 0x13a
	BTN_START                 = 0x13b
	BTN_MODE                  = 0x13c
	BTN_THUMBL                = 0x13d
	BTN_THUMBR                = 0x13e
	ABS_X                     = 0x00
	ABS_Y                     = 0x01
	ABS_Z                     = 0x02
	ABS_RX                    = 0x03
	ABS_RY                    = 0x04
	ABS_RZ                    = 0x05
	ABS_HAT0X                 = 0x10
	ABS_HAT0Y                 = 0x11
	RECONNECT_DELAY           = 500 * time.Millisecond
	READ_TIMEOUT              = 100 * time.Millisecond
	WRITE_TIMEOUT             = 100 * time.Millisecond
	STATUS_CHECK_INTERVAL     = 5 * time.Second
	CONNECTION_STATS_INTERVAL = 30 * time.Second
	JS_EVENT_INIT             = 0x80
	JS_EVENT_SYNC             = 0xCD
)

var SOCKET_PATHS = []string{
	"/tmp/selkies_js0.sock",
	"/tmp/selkies_js1.sock",
	"/tmp/selkies_js2.sock",
	"/tmp/selkies_js3.sock",
}

// JoystickEvent 结构体定义
// 匹配Python的struct.pack('IhBB')格式:
// I: uint32 - 时间戳
// h: int16  - 值
// B: uint8  - 类型
// B: uint8  - 编号
type JoystickEvent struct {
	Time   uint32 // 4字节, unsigned int
	Value  int16  // 2字节, signed short
	Type   uint8  // 1字节, unsigned char
	Number uint8  // 1字节, unsigned char
}

type ConnectionStats struct {
	eventsReceived uint64
	eventsSent     uint64
	errors         uint64
	lastActive     time.Time
	latency        time.Duration
	mu             sync.Mutex
}

func (s *ConnectionStats) update(eventType string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	start := time.Now()
	switch eventType {
	case "received":
		s.eventsReceived++
	case "sent":
		s.eventsSent++
	case "error":
		s.errors++
	}
	s.lastActive = time.Now()
	s.latency = time.Since(start)
}

type JoystickClient struct {
	conn     net.Conn
	deviceID int
	stats    *ConnectionStats
}

type XPADConfig struct {
	btnMap    map[uint8]int
	axesMap   map[uint8]int
	axesToBtn map[uint8][]uint8
}

func newXPADConfig() *XPADConfig {
	cfg := &XPADConfig{
		btnMap: map[uint8]int{
			0:  BTN_A,
			1:  BTN_B,
			2:  BTN_X,
			3:  BTN_Y,
			4:  BTN_TL,
			5:  BTN_TR,
			6:  BTN_SELECT,
			7:  BTN_START,
			8:  BTN_MODE,
			9:  BTN_THUMBL,
			10: BTN_THUMBR,
		},
		axesMap: map[uint8]int{
			0: ABS_X,
			1: ABS_Y,
			2: ABS_Z,
			3: ABS_RX,
			4: ABS_RY,
			5: ABS_RZ,
			6: ABS_HAT0X,
			7: ABS_HAT0Y,
		},
		axesToBtn: map[uint8][]uint8{
			2: {L2_BUTTON},
			5: {R2_BUTTON},
			6: {DPAD_LEFT, DPAD_RIGHT},
			7: {DPAD_DOWN, DPAD_UP},
		},
	}
	return cfg
}

type Config struct {
	DeviceID       int
	Name           string
	NumButtons     int
	NumAxes        int
	EventQueueSize int
	ReadTimeout    time.Duration
	WriteTimeout   time.Duration
	btnMap         map[uint8]int
	axesMap        map[uint8]int
	axesToBtn      map[uint8][]uint8
}

func NewConfig() Config {
	return Config{
		btnMap: map[uint8]int{
			0:  BTN_A,
			1:  BTN_B,
			2:  BTN_X,
			3:  BTN_Y,
			4:  BTN_TL,
			5:  BTN_TR,
			6:  BTN_SELECT,
			7:  BTN_START,
			8:  BTN_MODE,
			9:  BTN_THUMBL,
			10: BTN_THUMBR,
		},
		axesMap: map[uint8]int{
			0: ABS_X,
			1: ABS_Y,
			2: ABS_Z,
			3: ABS_RX,
			4: ABS_RY,
			5: ABS_RZ,
			6: ABS_HAT0X,
			7: ABS_HAT0Y,
		},
		axesToBtn: map[uint8][]uint8{
			2: {L2_BUTTON},
			5: {R2_BUTTON},
			6: {DPAD_LEFT, DPAD_RIGHT},
			7: {DPAD_DOWN, DPAD_UP},
		},
	}
}

type EventQueue struct {
	events chan JoystickEvent
	mu     sync.Mutex
}

func NewEventQueue(size int) *EventQueue {
	return &EventQueue{
		events: make(chan JoystickEvent, size),
	}
}

type JoystickHandler struct {
	mu         sync.RWMutex
	devices    map[int]*os.File
	sdlDevices map[int]*sdl.Joystick
	events     *EventQueue
	config     Config
	stats      map[int]*ConnectionStats
}

func NewJoystickHandler(config Config) *JoystickHandler {
	h := &JoystickHandler{
		devices:    make(map[int]*os.File),
		sdlDevices: make(map[int]*sdl.Joystick),
		events:     NewEventQueue(128),
		config:     config,
		stats:      make(map[int]*ConnectionStats),
	}

	// 启动���件处理goroutine
	go h.processEvents()
	log.Printf("事件处理循环已启动")

	return h
}

func (h *JoystickHandler) processEvents() {
	log.Printf("开始处理事件...")
	for event := range h.events.events {
		h.mu.RLock()
		device := h.devices[h.config.DeviceID]
		h.mu.RUnlock()

		if device == nil {
			log.Printf("警告: 设备未初始化，跳过事件处理")
			continue
		}

		// 写入事件到设备文件
		if err := binary.Write(device, binary.LittleEndian, event); err != nil {
			log.Printf("写入事件失败: %v", err)
			continue
		}

		log.Printf("事件已写入: 类型=%d, 编号=%d, 值=%d",
			event.Type, event.Number, event.Value)
	}
}

func (h *JoystickHandler) handleButtonEvent(joystick *sdl.Joystick, event JoystickEvent) {
	if btn, ok := h.config.btnMap[event.Number]; ok {
		log.Printf("按钮事件: number=%d -> %d, value=%d", event.Number, btn, event.Value)

		// 创建并发送SDL按钮事件
		buttonEvent := sdl.JoyButtonEvent{
			Type:      sdl.JOYBUTTONDOWN,
			Which:     0, // 使用固定的设备ID
			Button:    uint8(event.Number),
			State:     uint8(event.Value),
			Timestamp: uint32(time.Now().UnixNano() / 1000000), // 毫秒时间戳
		}
		if event.Value == 0 {
			buttonEvent.Type = sdl.JOYBUTTONUP
		}
		sdl.PushEvent(&buttonEvent)
	}
}

func (h *JoystickHandler) handleAxisEvent(joystick *sdl.Joystick, event JoystickEvent) {
	// 检查是否需要转换为按钮事件
	if btns, ok := h.config.axesToBtn[event.Number]; ok {
		if len(btns) == 1 {
			// 触发器类型 (L2/R2)
			value := int16((float64(event.Value-ABS_MIN) / float64(ABS_MAX-ABS_MIN)) * 32767)
			log.Printf("触发器事件: axis=%d -> button=%d, value=%d", event.Number, btns[0], value)

			// 发送触发按钮事件
			buttonEvent := sdl.JoyButtonEvent{
				Type:   sdl.JOYBUTTONDOWN,
				Which:  sdl.JoystickID(joystick.InstanceID()),
				Button: btns[0],
				State:  uint8(map[bool]int{true: 1, false: 0}[value > 0]),
			}
			sdl.PushEvent(&buttonEvent)

		} else if len(btns) == 2 {
			// D-pad类型
			var pressedBtn uint8
			if event.Value < 0 {
				pressedBtn = btns[0]
				log.Printf("D-pad事件: axis=%d -> button=%d, pressed", event.Number, btns[0])
			} else if event.Value > 0 {
				pressedBtn = btns[1]
				log.Printf("D-pad事件: axis=%d -> button=%d, pressed", event.Number, btns[1])
			}

			// 发送D-pad按钮事件
			for _, btn := range btns {
				buttonEvent := sdl.JoyButtonEvent{
					Type:   sdl.JOYBUTTONDOWN,
					Which:  sdl.JoystickID(joystick.InstanceID()),
					Button: btn,
					State:  uint8(map[bool]int{true: 1, false: 0}[btn == pressedBtn]),
				}
				if btn != pressedBtn {
					buttonEvent.Type = sdl.JOYBUTTONUP
				}
				sdl.PushEvent(&buttonEvent)
			}

		}
	} else if axis, ok := h.config.axesMap[event.Number]; ok {
		// 普通轴事件
		log.Printf("轴事件: number=%d -> %d, value=%d", event.Number, axis, event.Value)

		// 发送SDL轴事件
		axisEvent := sdl.JoyAxisEvent{
			Type:  sdl.JOYAXISMOTION,
			Which: sdl.JoystickID(joystick.InstanceID()),
			Axis:  uint8(axis),
			Value: int16(event.Value),
		}
		sdl.PushEvent(&axisEvent)
	}
}

func (h *JoystickHandler) addJoystick(deviceID int) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if _, exists := h.devices[deviceID]; !exists {
		// 打印SDL相关环境变量
		log.Printf("\nSDL环境变量:")
		if device := os.Getenv("SDL_JOYSTICK_DEVICE"); device != "" {
			log.Printf("SDL_JOYSTICK_DEVICE: %s", device)
		} else {
			log.Printf("SDL_JOYSTICK_DEVICE: 未设置")
		}

		if config := os.Getenv("SDL_GAMECONTROLLERCONFIG"); config != "" {
			log.Printf("SDL_GAMECONTROLLERCONFIG: %s", config)
		} else {
			log.Printf("SDL_GAMECONTROLLERCONFIG: 未设置")
		}

		// 创建拟设备
		sdl.JoystickEventState(sdl.ENABLE)

		// 使用 SDL_GameController 初始化
		if gameController := sdl.GameControllerOpen(deviceID); gameController != nil {
			h.sdlDevices[deviceID] = gameController.Joystick()
			log.Printf("添加SDL游戏控制器: ID=%d, 名称: %s",
				deviceID, gameController.Name())
		} else {
			// 如果无法创建游戏控制器，创建基本的手柄设备
			if joystick := sdl.JoystickOpen(deviceID); joystick != nil {
				h.sdlDevices[deviceID] = joystick
				log.Printf("添加SDL手柄: ID=%d, 名称: %s",
					deviceID, joystick.Name())
			} else {
				// 创建基本的虚拟手柄
				h.devices[deviceID] = nil
				log.Printf("创建虚拟手柄设备: ID=%d", deviceID)
			}
		}

		// 初始化设备状态
		h.initializeDeviceState(deviceID)
	}
}

func (h *JoystickHandler) initializeDeviceState(deviceID int) {
	joystick := h.devices[deviceID]
	if joystick == nil {
		return
	}

	// 初始化按钮状态
	for i := 0; i < h.config.NumButtons; i++ {
		event := JoystickEvent{
			Time:   uint32(time.Now().UnixNano() / 1000000),
			Value:  0,
			Type:   JS_EVENT_BUTTON,
			Number: uint8(i),
		}
		h.handleEvent(deviceID, event)
	}

	// 初始化轴状态
	for i := 0; i < h.config.NumAxes; i++ {
		event := JoystickEvent{
			Time:   uint32(time.Now().UnixNano() / 1000000),
			Value:  0,
			Type:   JS_EVENT_AXIS,
			Number: uint8(i),
		}
		h.handleEvent(deviceID, event)
	}

	log.Printf("设备状态初始化完成: ID=%d", deviceID)
}

func (h *JoystickHandler) removeJoystick(deviceID int) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if joystick, exists := h.devices[deviceID]; exists {
		joystick.Close()
		delete(h.devices, deviceID)
		log.Printf("移除手柄: ID=%d", deviceID)
	}
}

func initLogger() {
	logFile, err := os.OpenFile(LOG_FILE, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		log.Fatalf("无法打开日志文件: %v", err)
	}

	log.SetOutput(logFile)
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)

	log.Println("初始化日志系统完成")
}

func connectToServer(socketPath string) (*JoystickClient, error) {
	log.Printf("尝试连接到 socket: %s", socketPath)

	// 添加重试逻辑
	maxRetries := 5
	for i := 0; i < maxRetries; i++ {
		if _, err := os.Stat(socketPath); os.IsNotExist(err) {
			log.Printf("socket 不存在等待创建: %s (尝试 %d/%d)",
				socketPath, i+1, maxRetries)
			time.Sleep(1 * time.Second)
			continue
		}

		conn, err := net.Dial("unix", socketPath)
		if err != nil {
			log.Printf("连接失败: %v (尝试 %d/%d)", err, i+1, maxRetries)
			time.Sleep(1 * time.Second)
			continue
		}

		log.Printf("成功连接到 socket: %s", socketPath)
		return &JoystickClient{
			conn:     conn,
			deviceID: 0,
			stats:    &ConnectionStats{lastActive: time.Now()},
		}, nil
	}

	return nil, fmt.Errorf("无法连接到 socket: %s，已达到最大重试次数", socketPath)
}

func reconnectClient(socketPath string, deviceID int) (*JoystickClient, error) {
	time.Sleep(RECONNECT_DELAY)
	client, err := connectToServer(socketPath)
	if err != nil {
		return nil, err
	}
	client.deviceID = deviceID
	return client, nil
}

func handleEvent(event JoystickEvent, client *JoystickClient) error {
	// 打印接收到的事件详情
	log.Printf("处理事件: time=%d, type=%d, number=%d, value=%d",
		event.Time, event.Type, event.Number, event.Value)

	// 发送事件到服务器
	if err := binary.Write(client.conn, binary.LittleEndian, event); err != nil {
		return fmt.Errorf("发送事件失败: %v", err)
	}
	return nil
}

var buttonNames = map[uint8]string{
	0x30: "A按钮",     // BTN_A & 0xFF
	0x31: "B按钮",     // BTN_B & 0xFF
	0x33: "X按钮",     // BTN_X & 0xFF
	0x34: "Y按钮",     // BTN_Y & 0xFF
	0x36: "LB按钮",    // BTN_TL & 0xFF
	0x37: "RB按钮",    // BTN_TR & 0xFF
	0x3a: "Back按钮",  // BTN_SELECT & 0xFF
	0x3b: "Start按钮", // BTN_START & 0xFF
	0x3c: "Xbox按钮",  // BTN_MODE & 0xFF
	0x3d: "左摇杆按钮",   // BTN_THUMBL & 0xFF
	0x3e: "右摇杆按钮",   // BTN_THUMBR & 0xFF
}

var axisNames = map[uint8]string{
	0: "左摇杆X轴",    // ABS_X
	1: "左摇杆Y轴",    // ABS_Y
	2: "左扳机",      // ABS_Z
	3: "右摇杆X轴",    // ABS_RX
	4: "右摇杆Y轴",    // ABS_RY
	5: "右扳机",      // ABS_RZ
	6: "D-Pad X轴", // ABS_HAT0X
	7: "D-Pad Y轴", // ABS_HAT0Y
}

func normalizeAxisValue(value int16) float64 {
	// 将原始值(-32767 到 32767)映射到-1.0到1.0
	return float64(value) / float64(ABS_MAX)
}

func handleClientEvents(deviceID int, conn net.Conn, handler *JoystickHandler,
	clients map[int]*JoystickClient, clientsMu *sync.Mutex) {

	// log.Printf("开始处理客户端 %d 的事件", deviceID)
	buffer := make([]byte, 8) // IhBB = 4+2+1+1 = 8字节

	for {
		// 读取完整的8字节数据
		n, err := io.ReadFull(conn, buffer)
		if err != nil {
			if err != io.EOF && !strings.Contains(err.Error(), "i/o timeout") {
				log.Printf("读取事件失败: %v", err)
			}
			return
		}

		if n != 8 {
			log.Printf("读取数据不完整: 期望8字节, 实际%d字节", n)
			continue
		}

		// 按Python的IhBB格式解析
		event := JoystickEvent{
			Time:   binary.LittleEndian.Uint32(buffer[0:4]),        // I: uint32
			Value:  int16(binary.LittleEndian.Uint16(buffer[4:6])), // h: int16
			Type:   buffer[6],                                      // B: uint8
			Number: buffer[7],                                      // B: uint8
		}

		// 调试输出
		// log.Printf("原始字节[IhBB]: % x", buffer)
		log.Printf("解析事件: time=%d value=%d type=%d number=%d",
			event.Time, event.Value, event.Type, event.Number)

		if event.Type == JS_EVENT_BUTTON {
			log.Printf("按钮事件: button=%d %s",
				event.Number, map[int16]string{0: "释放", 1: "按下"}[event.Value])
			// 发送事件到uinput
			if err := handler.handleEvent(deviceID, event); err != nil {
				log.Printf("处理按钮事件失败: %v", err)
			}
		} else if event.Type == JS_EVENT_AXIS {
			log.Printf("轴事件: axis=%d value=%d",
				event.Number, event.Value)
			if err := handler.handleEvent(deviceID, event); err != nil {
				log.Printf("处理按钮事件失败: %v", err)
			}
		}
	}
}

// 从socket路径中提取设备ID
func extractDeviceID(socketPath string) int {
	// 从路径中提取数字
	re := regexp.MustCompile(`js(\d+)\.sock$`)
	matches := re.FindStringSubmatch(socketPath)
	if len(matches) > 1 {
		if id, err := strconv.Atoi(matches[1]); err == nil {
			return id
		}
	}
	return -1
}

func monitorSockets(clients map[int]*JoystickClient, clientsMu *sync.Mutex, handler *JoystickHandler) {
	// 记录上一次连接状态
	connectionAttempts := make(map[string]bool)

	for {
		for _, socketPath := range SOCKET_PATHS {
			// 检查socket文件是否存在
			if _, err := os.Stat(socketPath); os.IsNotExist(err) {
				continue
			}

			deviceID := extractDeviceID(socketPath)
			if deviceID == -1 {
				continue
			}

			// 检查是否已连接
			clientsMu.Lock()
			_, exists := clients[deviceID]
			clientsMu.Unlock()

			if exists {
				continue
			}

			// 检查是否是首次尝试连接
			if !connectionAttempts[socketPath] {
				log.Printf("开始尝试连接到 socket: %s (设备ID: %d)", socketPath, deviceID)
				connectionAttempts[socketPath] = true
			}

			// 尝试连接
			conn, err := net.Dial("unix", socketPath)
			if err != nil {
				time.Sleep(time.Second)
				continue
			}

			// 连接成功，重置状态
			connectionAttempts[socketPath] = false
			log.Printf("成功连接到 socket: %s (设备ID: %d)", socketPath, deviceID)

			// 读取配置数据
			// 255sHH512H64B
			configBuffer := make([]byte, 1349)
			n, err := conn.Read(configBuffer)
			if err != nil {
				log.Printf("读取配置数据失败: %v", err)
				conn.Close()
				continue
			}

			// 解析配置数据
			nameBytes := configBuffer[:255]
			name := string(bytes.TrimRight(nameBytes, "\x00"))

			// 初始化SDL设备
			if err := handler.initializeJoystick(deviceID); err != nil {
				log.Printf("SDL设备初始化失败 (ID: %d): %v", deviceID, err)
				conn.Close()
				continue
			}

			log.Printf("接收到手柄配置: 名称=%s, 数据大小=%d字节, SDL设备ID=%d",
				name, n, deviceID)

			clientsMu.Lock()
			clients[deviceID] = &JoystickClient{
				conn:     conn,
				deviceID: deviceID,
				stats:    &ConnectionStats{lastActive: time.Now()},
			}
			clientsMu.Unlock()

			log.Printf("成功初始化��柄客户: ID=%d", deviceID)

			// 启动事件处理
			go handleClientEvents(deviceID, conn, handler, clients, clientsMu)
		}
		time.Sleep(time.Second)
	}
}

func monitorConnectionStats(clients map[int]*JoystickClient, clientsMu *sync.Mutex) {
	ticker := time.NewTicker(CONNECTION_STATS_INTERVAL)
	defer ticker.Stop()

	for range ticker.C {
		clientsMu.Lock()
		for id, client := range clients {
			stats := client.stats
			stats.mu.Lock()
			log.Printf("连接状态 (设备 ID: %d):\n"+
				"  已接收事件: %d\n"+
				"  已发送事件: %d\n"+
				"  错误次数: %d\n"+
				"  最后活动: %v\n"+
				"  延迟: %v",
				id,
				stats.eventsReceived,
				stats.eventsSent,
				stats.errors,
				time.Since(stats.lastActive),
				stats.latency)
			stats.mu.Unlock()
		}
		clientsMu.Unlock()
	}
}

func handleJoystickEvent(event JoystickEvent) {
	switch event.Type {
	case JS_EVENT_BUTTON:
		// 处理按钮事件
		log.Printf("按钮事件: number=%d, value=%d", event.Number, event.Value)
		// 这里可以根据 STANDARD_XPAD_CONFIG 的映射关系转换按钮编号

	case JS_EVENT_AXIS:
		// 处理轴事件
		log.Printf("事件: number=%d, value=%d", event.Number, event.Value)
		// 这里要处理特的到按的映射
		// 比如 D-pad 和触发器的映射
	}
}

type LogState struct {
	deviceStatus map[int]bool
	errorState   struct {
		lastErrorTime    time.Time
		lastRecoveryTime time.Time
		errorCount       int
		isInErrorState   bool
		deviceErrors     map[int]bool
		connectionErrors map[string]bool
	}
	mu sync.Mutex
}

var logState = LogState{
	deviceStatus: make(map[int]bool),
	errorState: struct {
		lastErrorTime    time.Time
		lastRecoveryTime time.Time
		errorCount       int
		isInErrorState   bool
		deviceErrors     map[int]bool
		connectionErrors map[string]bool
	}{
		deviceErrors:     make(map[int]bool),
		connectionErrors: make(map[string]bool),
	},
}

func handleEvents(client *JoystickClient, handler *JoystickHandler) {
	// 确保设备初始化并等待初始化完成
	if err := handler.initializeJoystick(client.deviceID); err != nil {
		log.Printf("设备初始化失败: %v", err)
		return
	}

	log.Printf("开始处理设备 %d 的事件", client.deviceID)

	// 读取并解析配置数据
	configBuffer := make([]byte, 1024)
	n, err := client.conn.Read(configBuffer)
	if err != nil {
		log.Printf("读取配置数据失败: %v", err)
		return
	}

	// 解析配置数据
	// 根据 js-interposer-test.py 中的格式：
	// struct_fmt = "255sHH%dH%dB" % (MAX_BTNS, MAX_AXES)
	nameBytes := configBuffer[:255]
	name := string(bytes.TrimRight(nameBytes, "\x00"))

	log.Printf("接收到手柄配置:")
	log.Printf("  名称: %s", name)
	log.Printf("  配置数据大小: %d 字节", n)

	// 事件处理循环
	buffer := make([]byte, 8)
	for {
		var totalRead int
		for totalRead < 8 {
			n, err := client.conn.Read(buffer[totalRead:])
			if err != nil {
				if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
					continue
				}
				log.Printf("读取错误: %v", err)
				return
			}
			totalRead += n
		}

		event := JoystickEvent{}
		if err := binary.Read(bytes.NewReader(buffer), binary.LittleEndian, &event); err != nil {
			log.Printf("解析事件失败: %v", err)
			continue
		}

		client.stats.update("received")
		handler.handleEvent(client.deviceID, event)
	}
}

func generateJoystickGUID(deviceID int) string {
	// 生成唯一的GUID
	// SDL GUID格式: 4字节(bus类型+厂商ID) + 4字节(产品ID) + 4字节(版本) + 4字节(CRC)
	// 例如: 03000000 + 5e040000 + 8e020000 + 14010000
	timestamp := time.Now().UnixNano()
	return fmt.Sprintf("%08x%08x%08x%08x",
		0x03000000,                 // USB bus type
		0x5e040000|(deviceID&0xFF), // 厂商ID (Microsoft) + deviceID
		timestamp&0xFFFFFFFF,       // 使用时间戳作为唯一标识
		0x14010000,                 // 固定版本号
	)
}

func (h *JoystickHandler) initializeJoystick(deviceID int) error {
	h.mu.Lock()
	defer h.mu.Unlock()

	// 设置SDL使用uinput
	os.Setenv("SDL_JOYSTICK_DEVICE", "/dev/uinput")
	os.Setenv("SDL_GAMECONTROLLERCONFIG_FILE", "")

	// 初始化SDL
	if sdl.WasInit(sdl.INIT_GAMECONTROLLER|sdl.INIT_JOYSTICK) == 0 {
		if err := sdl.Init(sdl.INIT_GAMECONTROLLER | sdl.INIT_JOYSTICK); err != nil {
			return fmt.Errorf("SDL初始化失败: %v", err)
		}
	}

	// 添加控制器映射
	guid := generateJoystickGUID(deviceID)
	controllerConfig := fmt.Sprintf("%s,Xbox 360 Controller,platform:Linux,...", guid)
	if result := sdl.GameControllerAddMapping(controllerConfig); result < 0 {
		log.Printf("控制器映射添加失败: %s", sdl.GetError())
	}

	// 创建虚拟设备
	if sdl.JoystickEventState(sdl.ENABLE) < 0 {
		log.Printf("事件状态设置失败: %s", sdl.GetError())
	}

	log.Printf("尝试创建虚拟设备...")
	return nil
}

func (h *JoystickHandler) handleEvent(deviceID int, event JoystickEvent) error {
	h.mu.RLock()
	device, exists := h.sdlDevices[deviceID]
	h.mu.RUnlock()

	if !exists || device == nil {
		// 尝试重新初始化设备
		if err := h.initializeJoystick(deviceID); err != nil {
			return fmt.Errorf("设备初始化失败: %v", err)
		}
		h.mu.RLock()
		device, exists = h.sdlDevices[deviceID]
		h.mu.RUnlock()

		if !exists || device == nil {
			return fmt.Errorf("设备初始化后仍然无效: ID=%d", deviceID)
		}
	}

	// 将远程事件转换为SDL事件
	switch event.Type {
	case JS_EVENT_BUTTON:
		buttonName := buttonNames[event.Number]
		if buttonName == "" {
			buttonName = fmt.Sprintf("按钮%d", event.Number)
		}

		sdlEvent := sdl.JoyButtonEvent{
			Type:      sdl.JOYBUTTONDOWN,
			Which:     sdl.JoystickID(device.InstanceID()), // 使用device获取实例ID
			Button:    uint8(event.Number),
			State:     uint8(event.Value),
			Timestamp: uint32(event.Time),
		}

		if event.Value == 0 {
			sdlEvent.Type = sdl.JOYBUTTONUP
			log.Printf("发送SDL按钮事件: %s 释放", buttonName)
		} else {
			log.Printf("发送SDL按钮事件: %s 按下", buttonName)
		}

		success, err := sdl.PushEvent(&sdlEvent)
		if !success {
			return fmt.Errorf("发送按钮事件失败: %v", err)
		}

	case JS_EVENT_AXIS:
		sdlEvent := sdl.JoyAxisEvent{
			Type:      sdl.JOYAXISMOTION,
			Which:     sdl.JoystickID(device.InstanceID()), // 使用device获取实例ID
			Axis:      uint8(event.Number),
			Value:     int16(event.Value),
			Timestamp: uint32(event.Time),
		}

		log.Printf("发送SDL轴事件: axis=%d value=%d", event.Number, event.Value)

		success, err := sdl.PushEvent(&sdlEvent)
		if !success {
			return fmt.Errorf("发送按钮事件失败: %v", err)
		}

	default:
		return fmt.Errorf("未知事件类型: 0x%x", event.Type)
	}

	return nil
}

// 辅助函数：计算绝对值
func abs(x int16) int16 {
	if x < 0 {
		return -x
	}
	return x
}

func logOnStateChange(category string, id int, status bool, message string) {
	static := struct {
		states map[string]bool
		mu     sync.Mutex
	}{
		states: make(map[string]bool),
	}

	static.mu.Lock()
	defer static.mu.Unlock()

	key := fmt.Sprintf("%s_%d", category, id)
	lastStatus, exists := static.states[key]

	if !exists || lastStatus != status {
		log.Printf(message)
		static.states[key] = status
	}
}

func main() {
	initLogger()
	log.Printf("启动手柄服务器，版本: 1.0.0")

	// 检查 socket 文件是否存在
	for _, socketPath := range SOCKET_PATHS {
		_, err := os.Stat(socketPath)
		if os.IsNotExist(err) {
			// log.Printf("等待 socket 文件创建: %s", socketPath)
		} else {
			log.Printf("发现 socket 文件: %s", socketPath)
		}
	}

	if err := sdl.Init(sdl.INIT_JOYSTICK); err != nil {
		log.Fatalf("SDL初始化失败: %v", err)
	}
	defer sdl.Quit()

	config := Config{
		DeviceID:       0,
		Name:           "Beagle Virtual Gamepad",
		NumButtons:     11,
		NumAxes:        8,
		EventQueueSize: 64,
		ReadTimeout:    100 * time.Millisecond,
		WriteTimeout:   100 * time.Millisecond,
	}

	handler := NewJoystickHandler(config)

	// 启动事件处理
	go handler.processEvents()

	clients := make(map[int]*JoystickClient)
	var clientsMu sync.Mutex

	// 启动监控
	go monitorSockets(clients, &clientsMu, handler)
	go monitorConnectionStats(clients, &clientsMu)

	// 添加个变量来跟踪上一次的连接数
	var lastConnectionCount int

	// 修改定期检查的逻辑
	go func() {
		ticker := time.NewTicker(1 * time.Second)
		defer ticker.Stop()

		for range ticker.C {
			clientsMu.Lock()
			currentCount := len(clients)

			// 只在连接数发生变化时输出日志
			if currentCount != lastConnectionCount {
				log.Printf("连接数变化: %d -> %d", lastConnectionCount, currentCount)
				lastConnectionCount = currentCount

				// 当有连接时，输出一次详细信息
				if currentCount > 0 {
					for id, client := range clients {
						log.Printf("活动客户端: ID=%d, 最后活动时间: %v",
							id,
							time.Since(client.stats.lastActive))
					}
				}
			}
			clientsMu.Unlock()
		}
	}()

	running := true
	for running {
		clientsMu.Lock()
		for i, client := range clients {
			event := JoystickEvent{}

			if err := client.conn.SetReadDeadline(time.Now().Add(READ_TIMEOUT)); err != nil {
				log.Printf("设置读取超时失败 (设备 ID: %d): %v", i, err)
				client.stats.update("error")
				continue
			}

			err := binary.Read(client.conn, binary.LittleEndian, &event)
			if err != nil {
				if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
					continue
				}

				if err == io.EOF {
					log.Printf("连接已关闭 (设备 ID: %d)", i)
				} else {
					log.Printf("读取事件失败 (设备 ID: %d): %v", i, err)
				}

				client.stats.update("error")
				handler.removeJoystick(i) // 移除SDL设备
				client.conn.Close()
				delete(clients, i)
				continue
			}

			client.stats.update("received")
			handler.handleEvent(i, event)
		}
		clientsMu.Unlock()
		sdl.Delay(16)
	}

	// 清理资源
	clientsMu.Lock()
	for _, client := range clients {
		client.conn.Close()
	}
	clientsMu.Unlock()

	handler.mu.Lock()
	for _, joystick := range handler.devices {
		joystick.Close()
	}
	handler.mu.Unlock()
}
