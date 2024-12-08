package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

const (
	LOG_FILE = "/tmp/selkies_js_go.log"
	// config事件类型: 255sHH512H64B
	CONFIG_SIZE = 1348 // 255 + 2 + 2 + 1024 + 64 字节

	// 事件类型
	JS_EVENT_BUTTON = 0x01
	JS_EVENT_AXIS   = 0x02
	JS_EVENT_INIT   = 0x80

	// Uinput事件类型
	EV_SYN        = 0x00 // 同步事件
	EV_KEY        = 0x01 // 按键事件
	EV_ABS        = 0x02 // 轴事件
	UI_SET_EVBIT  = 0x40045564
	UI_SET_KEYBIT = 0x40045565
	UI_SET_ABSBIT = 0x40045566
	UI_DEV_CREATE = 0x40045567

	// Xbox 360手柄按钮映射
	BTN_A      = 0x130
	BTN_B      = 0x131
	BTN_X      = 0x133
	BTN_Y      = 0x134
	BTN_TL     = 0x136
	BTN_TR     = 0x137
	BTN_SELECT = 0x13a
	BTN_START  = 0x13b
	BTN_MODE   = 0x13c
	BTN_THUMBL = 0x13d
	BTN_THUMBR = 0x13e

	// 轴映射
	ABS_X     = 0x00
	ABS_Y     = 0x01
	ABS_Z     = 0x02
	ABS_RX    = 0x03
	ABS_RY    = 0x04
	ABS_RZ    = 0x05
	ABS_HAT0X = 0x10
	ABS_HAT0Y = 0x11
)

// JoystickEvent 结构体定义 (匹配Python的IhBB格式)
type JoystickEvent struct {
	Time   uint32 // 4字节
	Value  int16  // 2字节
	Type   uint8  // 1字节
	Number uint8  // 1字节
}

// JoystickConfig 结构体定义 (匹配Python的255sHH512H64B格式)
type JoystickConfig struct {
	Name    [255]byte   // 设备名称
	NumBtns uint16      // 按钮数量
	NumAxes uint16      // 轴数量
	BtnMap  [512]uint16 // 按钮映射
	AxesMap [64]uint8   // 轴映射
}

// JoystickHandler 处理手柄事件
type JoystickHandler struct {
	mu         sync.RWMutex
	uinputFd   *os.File // uinput设备文件
	deviceID   int      // 设备ID
	socketConn net.Conn // socket连接
}

func NewJoystickHandler() *JoystickHandler {
	return &JoystickHandler{}
}

// 1. 连接Socket服务
func (h *JoystickHandler) connectToSocket(socketPath string) error {
	conn, err := net.Dial("unix", socketPath)
	if err != nil {
		return fmt.Errorf("连接socket失败: %v", err)
	}

	h.socketConn = conn
	log.Printf("成功连接到socket: %s", socketPath)

	// 读取配置数据
	config, err := h.readConfig()
	if err != nil {
		return fmt.Errorf("读取配置失败: %v", err)
	}

	// 使用配置初始化uinput设备
	return h.initUinputDevice(config)
}

// 2. 创建Uinput���备
func (h *JoystickHandler) initUinputDevice(config *JoystickConfig) error {
	// 打开uinput设备
	fd, err := os.OpenFile("/dev/uinput", os.O_WRONLY|syscall.O_NONBLOCK, 0660)
	if err != nil {
		return fmt.Errorf("打开uinput设备失败: %v", err)
	}
	h.uinputFd = fd

	// 配置设备功能
	if err := h.setupUinputDevice(config); err != nil {
		return err
	}

	log.Printf("成功创建uinput设备")
	return nil
}

// 3. 事件处理循环
func (h *JoystickHandler) processEvents() {
	buffer := make([]byte, 8) // IhBB = 4+2+1+1 = 8字节

	for {
		// 读取事件数据
		_, err := io.ReadFull(h.socketConn, buffer)
		if err != nil {
			log.Printf("读取事件失败: %v", err)
			return
		}

		// 解析事件 (4字节时间戳 + 2字节值 + 1字节类型 + 1字节编号)
		event := JoystickEvent{
			Time:   binary.LittleEndian.Uint32(buffer[0:4]),        // 4字节时间戳
			Value:  int16(binary.LittleEndian.Uint16(buffer[4:6])), // 2字节值
			Type:   buffer[6],                                      // 1字节类型
			Number: buffer[7],                                      // 1字节编号
		}

		// 打印事件数据
		log.Printf("收到事件: 时间戳=%d, 值=%d, 类型=0x%x, 编号=%d (原始数据: %v)",
			event.Time, event.Value, event.Type, event.Number, buffer)

		// 转发到uinput设备
		if err := h.forwardEvent(event); err != nil {
			log.Printf("转发事件失败: %v", err)
			continue
		}
	}
}

// 按钮映射表
var buttonMap = []uint16{
	BTN_A,      // 0: 0x130
	BTN_B,      // 1: 0x131
	BTN_X,      // 2: 0x133
	BTN_Y,      // 3: 0x134
	BTN_TL,     // 4: 0x136
	BTN_TR,     // 5: 0x137
	BTN_SELECT, // 6: 0x13a
	BTN_START,  // 7: 0x13b
	BTN_MODE,   // 8: 0x13c
	BTN_THUMBL, // 9: 0x13d
	BTN_THUMBR, // 10: 0x13e
}

// 转发事件到uinput设备
func (h *JoystickHandler) forwardEvent(event JoystickEvent) error {
	h.mu.RLock()
	defer h.mu.RUnlock()

	eventType := event.Type & ^uint8(JS_EVENT_INIT)

	switch eventType {
	case JS_EVENT_BUTTON:
		// 获取映射的按钮代码
		if int(event.Number) >= len(buttonMap) {
			return fmt.Errorf("按钮编号超出范围: %d", event.Number)
		}
		btnCode := buttonMap[event.Number]

		log.Printf("按钮映射: 原始编号=%d, 映射代码=0x%x", event.Number, btnCode)

		// 转换为uinput按键事件
		err := h.writeUinputEvent(EV_KEY, btnCode, event.Value)
		if err != nil {
			return fmt.Errorf("写入按键事件失败: %v", err)
		}
		// 发送同步事件
		return h.writeUinputEvent(EV_SYN, 0, 0)

	case JS_EVENT_AXIS:
		// 转换为uinput轴事件
		err := h.writeUinputEvent(EV_ABS, uint16(event.Number), event.Value)
		if err != nil {
			return fmt.Errorf("写入轴事件失败: %v", err)
		}
		// 发送同步事件
		return h.writeUinputEvent(EV_SYN, 0, 0)

	case 0: // 同步事件
		return h.writeUinputEvent(EV_SYN, 0, 0)

	default:
		return fmt.Errorf("未知事件类型: %d", eventType)
	}
}

func (h *JoystickHandler) readConfig() (*JoystickConfig, error) {
	config := &JoystickConfig{}
	buffer := make([]byte, CONFIG_SIZE)

	// 读取完整配置数据
	if _, err := io.ReadFull(h.socketConn, buffer); err != nil {
		return nil, fmt.Errorf("读取配置数据失败: %v", err)
	}

	// 解析配置
	copy(config.Name[:], buffer[:255])
	config.NumBtns = binary.LittleEndian.Uint16(buffer[255:257])
	config.NumAxes = binary.LittleEndian.Uint16(buffer[257:259])

	return config, nil
}

func (h *JoystickHandler) writeUinputEvent(eventType uint16, code uint16, value int16) error {
	// Linux input_event结构体
	type InputEvent struct {
		Time  syscall.Timeval // 16字节
		Type  uint16          // 2字节
		Code  uint16          // 2字节
		Value int32           // 4字节
	}

	// 获取当前时间
	now := time.Now()
	tv := syscall.Timeval{
		Sec:  now.Unix(),
		Usec: int64(now.Nanosecond() / 1000),
	}

	// 创建事件
	event := InputEvent{
		Time:  tv,
		Type:  eventType,
		Code:  code,
		Value: int32(value),
	}

	// 使用unsafe直接写入
	size := int(unsafe.Sizeof(event))
	b := (*[64]byte)(unsafe.Pointer(&event))[:size:size]

	n, err := h.uinputFd.Write(b)
	if err != nil {
		return fmt.Errorf("写入事件失败: %v (类型: 0x%x, 代码: 0x%x, 值: %d, 写入字节: %d)",
			err, eventType, code, value, n)
	}

	log.Printf("写入事件: 类型=0x%x, 代码=0x%x, 值=%d, 字节数=%d",
		eventType, code, value, n)

	return nil
}

func (h *JoystickHandler) setupUinputDevice(config *JoystickConfig) error {
	// 1. 设置事件类型
	if err := ioctl(h.uinputFd, UI_SET_EVBIT, uintptr(EV_KEY)); err != nil {
		return fmt.Errorf("设置按键事件类型失败: %v", err)
	}
	if err := ioctl(h.uinputFd, UI_SET_EVBIT, uintptr(EV_ABS)); err != nil {
		return fmt.Errorf("设置轴事件类型失败: %v", err)
	}
	if err := ioctl(h.uinputFd, UI_SET_EVBIT, uintptr(EV_SYN)); err != nil {
		return fmt.Errorf("设置同步事件类型失败: %v", err)
	}

	// 2. 配置所有可能的按钮
	buttons := []uint16{
		BTN_A, BTN_B, BTN_X, BTN_Y, // 0x130-0x134
		BTN_TL, BTN_TR, // 0x136-0x137
		BTN_SELECT, BTN_START, // 0x13a-0x13b
		BTN_MODE,               // 0x13c
		BTN_THUMBL, BTN_THUMBR, // 0x13d-0x13e
	}

	log.Printf("正在配置按钮...")
	for _, btn := range buttons {
		if err := ioctl(h.uinputFd, UI_SET_KEYBIT, uintptr(btn)); err != nil {
			return fmt.Errorf("配置按钮失败 (按钮代码: 0x%x): %v", btn, err)
		}
		log.Printf("配置按钮: 0x%x", btn)
	}

	// 3. 配置轴
	var usetup struct {
		Name [80]byte
		ID   struct {
			BusType uint16
			Vendor  uint16
			Product uint16
			Version uint16
		}
		FF_EFFECTS_MAX uint32
		Absmax         [64]int32
		Absmin         [64]int32
		Absfuzz        [64]int32
		Absflat        [64]int32
	}

	// 设置设备名称
	name := bytes.TrimRight(config.Name[:], "\x00")
	copy(usetup.Name[:], name)

	// 配置所有轴
	axes := []uint16{
		ABS_X,  // 0: 左摇杆X
		ABS_Y,  // 1: 左摇杆Y
		ABS_Z,  // 2: 左扳机
		ABS_RX, // 3: 右摇杆X
		ABS_RY, // 4: 右摇杆Y
		ABS_RZ, // 5: 右扳机
	}

	// 配置轴
	for _, axis := range axes {
		if err := ioctl(h.uinputFd, UI_SET_ABSBIT, uintptr(axis)); err != nil {
			return fmt.Errorf("配置轴失败 (轴ID: 0x%x): %v", axis, err)
		}
		usetup.Absmax[axis] = 32767
		usetup.Absmin[axis] = -32767
		usetup.Absfuzz[axis] = 16
		usetup.Absflat[axis] = 128
	}

	// 写入设备信息
	if err := binary.Write(h.uinputFd, binary.LittleEndian, &usetup); err != nil {
		return fmt.Errorf("设置设备信息失败: %v", err)
	}

	// 创建设备
	if err := ioctl(h.uinputFd, UI_DEV_CREATE, 0); err != nil {
		return fmt.Errorf("创建设备失败: %v", err)
	}

	log.Printf("成功设置uinput设备: %s", name)
	return nil
}

func ioctl(fd *os.File, request, arg uintptr) error {
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd.Fd(), request, arg)
	if errno != 0 {
		return errno
	}
	return nil
}

func initLogger() {
	logFile, err := os.OpenFile(LOG_FILE, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		log.Fatalf("无法打开日志文件: %v", err)
	}
	log.SetOutput(logFile)
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds)
}

func main() {
	// 初始化日志
	initLogger()
	log.Printf("启动手柄事件转发服务")

	// 创建处理器
	handler := NewJoystickHandler()

	// 连接socket
	socketPath := "/tmp/selkies_js0.sock"
	if err := handler.connectToSocket(socketPath); err != nil {
		log.Fatalf("连接失败: %v", err)
	}

	// 开始事件处理循环
	handler.processEvents()
}
