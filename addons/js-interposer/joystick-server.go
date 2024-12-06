package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"log"
	"net"
	"os"
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
)

var SOCKET_PATHS = []string{
	"/tmp/selkies_js0.sock",
	"/tmp/selkies_js1.sock",
	"/tmp/selkies_js2.sock",
	"/tmp/selkies_js3.sock",
}

type JoystickEvent struct {
	Time   uint32
	Value  int16
	Type   uint8
	Number uint8
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
	mu        sync.RWMutex
	joysticks map[int]*sdl.Joystick
	config    Config
	events    *EventQueue
	stats     *ConnectionStats
}

func NewJoystickHandler(config Config) *JoystickHandler {
	return &JoystickHandler{
		joysticks: make(map[int]*sdl.Joystick),
		config:    config,
		events:    NewEventQueue(config.EventQueueSize),
		stats:     &ConnectionStats{lastActive: time.Now()},
	}
}

func (h *JoystickHandler) processEvents() {
	for event := range h.events.events {
		h.mu.RLock()
		joystick := h.joysticks[h.config.DeviceID]
		h.mu.RUnlock()

		if joystick == nil {
			continue
		}

		switch event.Type {
		case JS_EVENT_BUTTON:
			h.handleButtonEvent(joystick, event)
		case JS_EVENT_AXIS:
			h.handleAxisEvent(joystick, event)
		}

		h.stats.update("processed")
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

			// 发送触发器按钮事件
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

// 添加手柄设备管理
func (h *JoystickHandler) addJoystick(deviceID int) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if _, exists := h.joysticks[deviceID]; !exists {
		// 尝试多种方式创建设备
		gameController := sdl.GameControllerOpen(deviceID)
		if gameController == nil {
			joystick := sdl.JoystickOpen(deviceID)
			if joystick == nil {
				log.Printf("无法打开SDL设备 ID=%d: %s", deviceID, sdl.GetError())

				// 创建虚拟设备
				sdl.JoystickEventState(sdl.ENABLE)
				h.joysticks[deviceID] = nil
				log.Printf("添加虚拟手柄设备: ID=%d\n"+
					"  类型: 虚拟Xbox控制器\n"+
					"  设备路径: /dev/input/js%d\n"+
					"  按钮数量: %d\n"+
					"  轴数量: %d",
					deviceID, deviceID,
					h.config.NumButtons,
					h.config.NumAxes)

				// 初始化所有按钮和轴的状态
				h.initializeDeviceState(deviceID)
			} else {
				h.joysticks[deviceID] = joystick
				log.Printf("添加SDL设备: ID=%d\n"+
					"  名称: %s\n"+
					"  按钮数量: %d\n"+
					"  轴数量: %d",
					deviceID,
					joystick.Name(),
					joystick.NumButtons(),
					joystick.NumAxes())
			}
		} else {
			h.joysticks[deviceID] = gameController.Joystick()
			log.Printf("添加SDL游戏控制器: ID=%d\n"+
				"  名称: %s",
				deviceID,
				gameController.Name())
		}
	}
}

func (h *JoystickHandler) initializeDeviceState(deviceID int) {
	// 初始化所有按钮为未按下状态
	for i := 0; i < h.config.NumButtons; i++ {
		event := JoystickEvent{
			Time:   uint32(time.Now().UnixNano() / 1000000),
			Value:  0,
			Type:   JS_EVENT_BUTTON,
			Number: uint8(i),
		}
		h.handleButtonEvent(h.joysticks[deviceID], event)
	}

	// 初始化所有轴为中立位置
	for i := 0; i < h.config.NumAxes; i++ {
		event := JoystickEvent{
			Time:   uint32(time.Now().UnixNano() / 1000000),
			Value:  0,
			Type:   JS_EVENT_AXIS,
			Number: uint8(i),
		}
		h.handleAxisEvent(h.joysticks[deviceID], event)
	}
}

func (h *JoystickHandler) removeJoystick(deviceID int) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if joystick, exists := h.joysticks[deviceID]; exists {
		joystick.Close()
		delete(h.joysticks, deviceID)
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
			log.Printf("socket 文件不存在，等待创建: %s (尝试 %d/%d)",
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
			deviceID: -1,
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

func monitorSockets(clients map[int]*JoystickClient, clientsMu *sync.Mutex, handler *JoystickHandler) {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	for range ticker.C {
		for i, socketPath := range SOCKET_PATHS {
			// 检查 socket 文件是否存在
			if _, err := os.Stat(socketPath); os.IsNotExist(err) {
				log.Printf("等待 socket 文件创建: %s", socketPath)
				continue
			}

			clientsMu.Lock()
			if _, exists := clients[i]; !exists {
				// socket 文件存在但未连接，尝试连接
				if client, err := connectToServer(socketPath); err == nil {
					clients[i] = client
					log.Printf("成功连接到手柄服务器: %s", socketPath)

					// 开始处理事件
					go handleEvents(client, handler)
				}
			}
			clientsMu.Unlock()
		}
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
		log.Printf("轴事件: number=%d, value=%d", event.Number, event.Value)
		// 这需要处理特殊的轴到按钮的映射
		// 比如 D-pad 和触发器的映射
	}
}

func (h *JoystickHandler) handleEvent(deviceID int, event JoystickEvent) {
	h.mu.RLock()
	joystick := h.joysticks[deviceID]
	h.mu.RUnlock()

	if joystick == nil {
		return
	}

	switch event.Type {
	case JS_EVENT_BUTTON:
		h.handleButtonEvent(joystick, event)
	case JS_EVENT_AXIS:
		h.handleAxisEvent(joystick, event)
	}
}

func handleEvents(client *JoystickClient, handler *JoystickHandler) {
	for {
		event := JoystickEvent{}
		if err := binary.Read(client.conn, binary.LittleEndian, &event); err != nil {
			if err == io.EOF {
				log.Printf("连接已关闭")
				break
			}
			log.Printf("读取事件失败: %v", err)
			client.stats.update("error")
			continue
		}

		client.stats.update("received")
		handler.handleEvent(client.deviceID, event)
	}
}

func main() {
	initLogger()
	log.Printf("启动手柄服务器，版本: 1.0.0")

	// 检查 socket 文件是否存在
	for _, socketPath := range SOCKET_PATHS {
		_, err := os.Stat(socketPath)
		if os.IsNotExist(err) {
			log.Printf("等待 socket 文件创建: %s", socketPath)
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
		Name:           "Selkies Virtual Gamepad",
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

	// 添加定期检查
	go func() {
		ticker := time.NewTicker(1 * time.Second)
		defer ticker.Stop()

		for range ticker.C {
			clientsMu.Lock()
			log.Printf("当前连接数: %d", len(clients))
			for id, client := range clients {
				log.Printf("客户端 ID: %d, 最后活动时间: %v",
					id,
					time.Since(client.stats.lastActive))
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
				handler.removeJoystick(i) // 移除SDL设
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

	// 清资源
	clientsMu.Lock()
	for _, client := range clients {
		client.conn.Close()
	}
	clientsMu.Unlock()

	handler.mu.Lock()
	for _, joystick := range handler.joysticks {
		joystick.Close()
	}
	handler.mu.Unlock()
}
