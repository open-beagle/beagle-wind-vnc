package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"sync"
	"syscall"
	"time"

	"github.com/sirupsen/logrus"
)

const (
	LOG_FILE = "/tmp/selkies_js_go.log"
	// config事件类型: 255sHH512H64B
	CONFIG_SIZE       = 1348 // 255 + 2 + 2 + 1024 + 64 字节
	uinputMaxNameSize = 80
	absSize           = 64

	// 事件类型
	JS_EVENT_BUTTON = 0x01
	JS_EVENT_AXIS   = 0x02
	JS_EVENT_INIT   = 0x80

	// Uinput事件类型
	EV_SYN         = 0x00 // 同步事件
	EV_KEY         = 0x01 // 按键事件
	EV_ABS         = 0x03 // 轴事件
	UI_SET_EVBIT   = 0x40045564
	UI_SET_KEYBIT  = 0x40045565
	UI_SET_ABSBIT  = 0x40045567
	UI_DEV_CREATE  = 0x5501
	UI_DEV_DESTROY = 0x5502

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
	Number uint8  // 1节
}

// JoystickConfig 结构体定义 (匹配Python的255sHH512H64B格式)
type JoystickConfig struct {
	Name         [255]byte   // 设备名称
	NumBtns      uint16      // 按钮数量
	NumAxes      uint16      // 轴数量
	BtnMap       [512]uint16 // 按钮映射
	AxesMap      [64]uint8   // 轴映射
	Manufacturer [64]byte    // 生产厂家名称
	ProductID    uint16      // 产品ID
	Version      uint16      // 版本号
}

// JoystickHandler 处理手柄事件
type JoystickHandler struct {
	mu         sync.RWMutex
	uinputFd   *os.File        // uinput设备文件
	deviceID   int             // 设备ID
	socketConn net.Conn        // socket连接
	config     *JoystickConfig // 存储配置
	socketPath string          // socket路径
}

type inputID struct {
	Bustype uint16
	Vendor  uint16
	Product uint16
	Version uint16
}

// translated to go from uinput.h
type uinputUserDev struct {
	Name       [uinputMaxNameSize]byte
	ID         inputID
	EffectsMax uint32
	Absmax     [absSize]int32
	Absmin     [absSize]int32
	Absfuzz    [absSize]int32
	Absflat    [absSize]int32
}

// 新增 boot 方法
func (h *JoystickHandler) boot() {
	for {
		if err := h.connectToSocket(); err != nil {
			logrus.Debugf("连接失败: %v", err)
		}
		if err := h.processEvents(); err != nil {
			logrus.Debugf("事件处理失败: %v，准备重新连接...", err)
			h.socketConn.Close()        // 关闭当前连接
			time.Sleep(2 * time.Second) // 等待2秒后重试
		}
	}
}

// 修改 NewJoystickHandler 函数以接收 socketPath 参数
func NewJoystickHandler(socketPath string) *JoystickHandler {
	return &JoystickHandler{
		config:     &JoystickConfig{}, // 初始化 config 字段
		socketPath: socketPath,        // 记录 socketPath
	}
}

// 1. 连接Socket服务
func (h *JoystickHandler) connectToSocket() error {
	var err error
	for {
		// 检查 socket 是否存在
		if _, err := os.Stat(h.socketPath); os.IsNotExist(err) {
			logrus.Debugf("socket 文件不存在: %s，等待创建...", h.socketPath)
			time.Sleep(2 * time.Second) // 等待2秒后重试
			continue
		}

		logrus.Debugf("发现连接socket: %s", h.socketPath)

		h.socketConn, err = net.Dial("unix", h.socketPath)
		if err == nil {
			logrus.Printf("成功连接到socket: %s", h.socketPath)
			break // 成功��接后退出循环
		}
		logrus.Debugf("连接socket失败: %v，等待重试...", err)
		time.Sleep(2 * time.Second) // 等待2秒后重试
	}

	// 读取配置数据
	config, err := h.readConfig()
	if err != nil {
		logrus.Errorf("读取配置失败: %v", err)
		return fmt.Errorf("读取配置失败: %v", err)
	}

	h.config = config // 将读取的配置存储到 config 字段中

	// 使用配置初始化uinput设备
	if err := h.initUinputDevice(h.config); err != nil {
		logrus.Errorf("初始化uinput设备失败: %v", err)
		return err
	}

	return nil
}

// 2. 创建Uinput设备
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
	return nil
}

// 3. 事件处理循环
func (h *JoystickHandler) processEvents() error {
	buffer := make([]byte, 8) // IhBB = 4+2+1+1 = 8字节

	for {
		// 读取事件数据
		_, err := io.ReadFull(h.socketConn, buffer)
		if err != nil {
			logrus.Errorf("读取事件失败: %v", err)
			return fmt.Errorf("读取事件失败: %v", err) // 返回错误以便在 boot 方法中处理
		}

		// 解析事件 (4字节时间戳 + 2字节值 + 1字节类型 + 1字节编号)
		event := JoystickEvent{
			Time:   binary.LittleEndian.Uint32(buffer[0:4]),        // 4字节时间戳
			Value:  int16(binary.LittleEndian.Uint16(buffer[4:6])), // 2字节值
			Type:   buffer[6],                                      // 1字节类型
			Number: buffer[7],                                      // 1字节编号
		}

		// 转发到uinput设备
		if err := h.forwardEvent(event); err != nil {
			logrus.Errorf("转发事件失败: %v", err)
			continue
		}
	}
}

// 转发事件到uinput设备
func (h *JoystickHandler) forwardEvent(event JoystickEvent) error {
	h.mu.RLock()
	defer h.mu.RUnlock()

	eventType := event.Type & ^uint8(JS_EVENT_INIT)

	switch eventType {
	case JS_EVENT_BUTTON:
		// 获取映射的按钮代码
		if int(event.Number) >= int(h.config.NumBtns) {
			return fmt.Errorf("按钮编号-超出范围: %d", event.Number)
		}
		btnCode := h.config.BtnMap[event.Number]

		logrus.Infof("按钮触发: 原始编号=%d, 映射代码=0x%x", event.Number, btnCode)

		// 转换为uinput按键事件
		err := h.writeUinputEvent(EV_KEY, btnCode, event.Value)
		if err != nil {
			return fmt.Errorf("按键事件-写入失败: %v", err)
		}
		// 发送同步事件
		return h.writeUinputEvent(EV_SYN, 0, 0)

	case JS_EVENT_AXIS:
		// 获取映射的轴代码
		if int(event.Number) >= int(h.config.NumAxes) {
			return fmt.Errorf("轴编号-超出范围: %d", event.Number)
		}
		axeCode := h.config.AxesMap[event.Number]

		logrus.Infof("轴触发: 原始编号=%d, 映射代码=0x%x", event.Number, axeCode)

		// 转换为uinput轴事件
		err := h.writeUinputEvent(EV_ABS, uint16(axeCode), event.Value)
		if err != nil {
			return fmt.Errorf("轴事件-写入失败: %v", err)
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
		logrus.Errorf("读取配置数据失败: %v", err)
		return nil, fmt.Errorf("读取配置数据失败: %v", err)
	}

	// 解析配置
	copy(config.Name[:], buffer[:255])                           // 设备名称
	config.NumBtns = binary.LittleEndian.Uint16(buffer[256:258]) // 按钮数量
	config.NumAxes = binary.LittleEndian.Uint16(buffer[258:260]) // 轴数量

	// 读取按钮映射
	for i := 0; i < int(config.NumBtns); i++ {
		config.BtnMap[i] = binary.LittleEndian.Uint16(buffer[260+i*2 : 260+(i+1)*2])
	}

	// 读取轴映射
	for i := 0; i < int(config.NumAxes); i++ {
		config.AxesMap[i] = buffer[260+2*512+i]
	}

	return config, nil
}

func (h *JoystickHandler) writeUinputEvent(eventType uint16, code uint16, value int16) error {
	// 检查 uinputFd 是否有效
	if h.uinputFd == nil {
		return fmt.Errorf("uinput 设备未初始化或已关闭")
	}

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

	// 使用 binary.Write 入事件
	if err := binary.Write(h.uinputFd, binary.LittleEndian, &event); err != nil {
		logrus.Errorf("写入事件失败: %v (类型: 0x%x, 代码: 0x%x, 值: %d)",
			err, eventType, code, value)
		return fmt.Errorf("写入事件失败: %v (类型: 0x%x, 代码: 0x%x, 值: %d)",
			err, eventType, code, value)
	}

	logrus.Debugf("写入事件: 类型=0x%x, 代码=0x%x, 值=%d",
		eventType, code, value)

	return nil
}

// 设备初始化
func (h *JoystickHandler) setupUinputDevice(config *JoystickConfig) error {
	// 从 socketPath 中提取数字
	socketFileName := filepath.Base(h.socketPath) // 获取 socket 文件名
	var controllerNumber int
	fmt.Sscanf(socketFileName, "selkies_js%d.sock", &controllerNumber) // 从文件名中提取数字

	// 设置设备名称
	deviceName := fmt.Sprintf("beagle controller %d", controllerNumber)

	// 写入设备信息
	logrus.Infof("正在写入设备信息...")
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
	copy(usetup.Name[:], deviceName)
	usetup.ID.BusType = 0x03
	usetup.ID.Vendor = 0x026d
	usetup.ID.Product = 0x0001
	usetup.ID.Version = 0x0001

	// 写入设备信息
	if err := binary.Write(h.uinputFd, binary.LittleEndian, &usetup); err != nil {
		logrus.Errorf("设置设备信息失败: %v", err)
		_ = h.uinputFd.Close()
		return fmt.Errorf("设置设备信息失败: %v", err)
	}

	// 初始化按钮
	err := ioctl(h.uinputFd, UI_SET_EVBIT, uintptr(EV_KEY))
	if err != nil {
		_ = h.uinputFd.Close()
		logrus.Errorf("设置按钮失败 : %v", err)
	}
	for i := 0; i < int(config.NumBtns); i++ {
		if err := ioctl(h.uinputFd, UI_SET_KEYBIT, uintptr(config.BtnMap[i])); err != nil {
			logrus.Errorf("设置按钮失败 (按钮代码: 0x%x): %v", config.BtnMap[i], err)
			_ = h.uinputFd.Close()
			return fmt.Errorf("设置按钮失败 (按钮代码: 0x%x): %v", config.BtnMap[i], err)
		}
		logrus.Infof("设置按钮-成功：按钮代码: 0x%x ", config.BtnMap[i])
	}

	// 初始化轴
	err = ioctl(h.uinputFd, UI_SET_EVBIT, uintptr(EV_ABS))
	if err != nil {
		_ = h.uinputFd.Close()
		logrus.Errorf("设置轴失败 : %v", err)
	}
	for i := 0; i < int(config.NumAxes); i++ {
		if err := ioctl(h.uinputFd, UI_SET_ABSBIT, uintptr(config.AxesMap[i])); err != nil {
			logrus.Errorf("设置轴失败 (轴ID: 0x%x): %v", config.AxesMap[i], err)
			_ = h.uinputFd.Close()
			return fmt.Errorf("设置轴失败 (轴ID: 0x%x): %v", config.AxesMap[i], err)
		}
		logrus.Infof("设置轴-成功：轴代码: 0x%x ", config.AxesMap[i])
	}

	// 创建设备
	logrus.Infof("正在激活设备...")
	if err := ioctl(h.uinputFd, UI_DEV_CREATE, uintptr(0)); err != nil {
		logrus.Errorf("创建设备失败: %v", err)
		_ = h.uinputFd.Close()
		return fmt.Errorf("创建设备失败: %v", err)
	}

	logrus.Infof("成功设置uinput设备: %s", deviceName)
	return nil
}

func ioctl(fd *os.File, request, arg uintptr) error {
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd.Fd(), request, arg)
	if errno != 0 {
		return errno
	}
	return nil
}

// 初始化日志
func initLogger() {
	logFile, err := os.OpenFile(LOG_FILE, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		log.Fatalf("无法打开日志文件: %v", err)
	}

	// 使用 logrus 设置日志输出
	logrus.SetOutput(logFile)
	logrus.SetFormatter(&logrus.TextFormatter{
		FullTimestamp: true,
	})

	// 检查环境变量以设置日志级别
	logLevel := os.Getenv("LOG_LEVEL")
	if logLevel == "DEBUG" {
		logrus.SetLevel(logrus.DebugLevel) // 设置日志级别为 Debug
	} else if logLevel == "INFO" {
		logrus.SetLevel(logrus.InfoLevel) // 默认设置为 Info 级别
	} else {
		logrus.SetLevel(logrus.InfoLevel) // 默认设置为 Info 级别
	}
}

func main() {
	// 初始化日志
	initLogger()
	logrus.Infof("启动手柄事件转发服务")

	// 创建处理器，传入 socketPath
	socketPath := "/tmp/selkies_js0.sock"
	handler := NewJoystickHandler(socketPath)

	// 启动处理器
	handler.boot()
}
