package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/open-beagle/beagle-wind-vnc/addons/js-interposer/pkg"
	"github.com/sirupsen/logrus"
)

const (
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
	EV_FF          = 0x15 // 力反馈事件
	UI_SET_EVBIT   = 0x40045564
	UI_SET_KEYBIT  = 0x40045565
	UI_SET_ABSBIT  = 0x40045567
	UI_DEV_CREATE  = 0x5501
	UI_DEV_DESTROY = 0x5502
	UI_SET_JSBIT   = 0x40045571

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
	Type   uint8  // 1节
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
	mu            sync.Mutex      // 互斥锁，确保对 uinputFd 的安全访问
	uinputFd      *os.File        // uinput设备文件
	uinputCreated bool            // uinput设备是否已创建
	deviceID      int             // 设备ID
	socketConn    net.Conn        // socket连接
	config        *JoystickConfig // 存储配置
	socketPath    string          // socket路径
	isStable      bool            // 是否稳定
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

// 0. 启动手柄事件转发服务
func (h *JoystickHandler) boot() {
	if h.isStable {
		h.bootStable()
	} else {
		h.bootDynamic()
	}
}

// 0.1. 启动手柄事件转发服务[动态]
func (h *JoystickHandler) bootDynamic() {
	for {
		// 连接Socket服务
		if err := h.connectToSocket(); err != nil {
			logrus.Debugf("连接失败: %v", err)
			time.Sleep(2 * time.Second) // 等待2秒后重试
			continue
		}
		// 读取配置数据
		if err := h.readConfig(); err != nil {
			logrus.Errorf("读取配置失败: %v", err)
			continue
		}
		// 使用配置初始化uinput设备
		if err := h.initUinputDevice(); err != nil {
			logrus.Errorf("初始化uinput设备失败: %v", err)
			continue
		}
		// 循环处理手柄事件
		if err := h.processEvents(); err != nil {
			logrus.Debugf("事件处理失败: %v，准备重新连接...", err)
			release()
		}
	}
}

// 0.2. 启动手柄事件转发服务[静态]
func (h *JoystickHandler) bootStable() {
	// 读取配置数据
	if err := h.createConfig(); err != nil {
		logrus.Errorf("创建配置失败: %v", err)
	}
	// 使用配置初始化uinput设备
	if err := h.initUinputDevice(); err != nil {
		logrus.Errorf("初始化uinput设备失败: %v", err)
	}
	for {
		// 连接Socket服务
		if err := h.connectToSocket(); err != nil {
			logrus.Debugf("连接失败: %v", err)
			time.Sleep(2 * time.Second) // 等待2秒后重试
			continue
		}
		// 读取配置数据
		if err := h.readConfig(); err != nil {
			logrus.Errorf("读取配置失败: %v", err)
			continue
		}
		// 循环处理手柄事件
		if err := h.processEvents(); err != nil {
			logrus.Debugf("事件处理失败: %v，准备重新连接...", err)
			release()
		}
	}
}

// 1. 连接Socket服务
func (h *JoystickHandler) connectToSocket() error {
	var err error
	// 检查 socket 是否存在
	if _, err := os.Stat(h.socketPath); os.IsNotExist(err) {
		logrus.Debugf("socket 文件不存在: %s，等待创建...", h.socketPath)
		return err
	}

	if h.socketConn, err = net.Dial("unix", h.socketPath); err != nil {
		logrus.Debugf("socket 文件: %s，连接失败 %v", h.socketPath, err)
		return err
	}

	logrus.Infof("成功连接到socket: %s", h.socketPath)
	return nil
}

// 2.1 读取手柄配置
func (h *JoystickHandler) readConfig() error {
	config := &JoystickConfig{}
	buffer := make([]byte, CONFIG_SIZE)

	// 读取完整配置数据
	if _, err := io.ReadFull(h.socketConn, buffer); err != nil {
		logrus.Errorf("读取配置数据失败: %v", err)
		return fmt.Errorf("读取配置数据失败: %v", err)
	}

	// 解析配置
	copy(config.Name[:], buffer[:255])                           // 设备名称
	config.NumBtns = binary.LittleEndian.Uint16(buffer[256:258]) // 按钮数量
	config.NumAxes = binary.LittleEndian.Uint16(buffer[258:260]) // 轴数量

	// 读取按钮映射
	for i := range make([]struct{}, config.NumBtns) {
		config.BtnMap[i] = binary.LittleEndian.Uint16(buffer[260+i*2 : 260+(i+1)*2])
	}

	// 读取轴映射
	for i := 0; i < int(config.NumAxes); i++ {
		config.AxesMap[i] = buffer[260+2*512+i]
	}

	h.config = config
	return nil
}

// 2.2 创建手柄配置
func (h *JoystickHandler) createConfig() error {
	config := &JoystickConfig{
		Name:    [255]byte{},
		NumBtns: 11,
		NumAxes: 8,
		BtnMap: [512]uint16{
			BTN_A,
			BTN_B,
			BTN_X,
			BTN_Y,
			BTN_TL,
			BTN_TR,
			BTN_SELECT,
			BTN_START,
			BTN_MODE,
			BTN_THUMBL,
			BTN_THUMBR,
		},
		AxesMap: [64]uint8{
			ABS_X,
			ABS_Y,
			ABS_Z,
			ABS_RX,
			ABS_RY,
			ABS_RZ,
			ABS_HAT0X,
			ABS_HAT0Y,
		},
	}
	copy(config.Name[:], "Xbox 360 Controller") // 将字符串复制到字节数组
	h.config = config
	return nil
}

// 3. Uinput - 创建设备
func (h *JoystickHandler) initUinputDevice() error {
	h.mu.Lock()         // 锁定以确保线程安全
	defer h.mu.Unlock() // 解锁

	// 打开uinput设备
	fd, err := os.OpenFile("/dev/uinput", os.O_WRONLY|syscall.O_NONBLOCK, 0660)
	if err != nil {
		return fmt.Errorf("打开uinput设备失败: %v", err)
	}
	h.uinputFd = fd

	// 配置设备功能
	if err := h.setupUinputDevice(); err != nil {
		return err
	}
	return nil
}

// 3.1. Uinput - 设备初始化
func (h *JoystickHandler) setupUinputDevice() error {
	// 创建设备前获取设备列表
	eventsBefore, _ := filepath.Glob("/dev/input/event*")
	joydevsBefore, _ := filepath.Glob("/dev/input/js*")

	// 1. 首先写入设备信息
	usetup := uinputUserDev{
		Name: [uinputMaxNameSize]byte{},
		ID: inputID{
			Bustype: 0x03,   // BUS_USB
			Vendor:  0x045e, // Microsoft
			Product: 0x028e, // Xbox360 controller
			Version: 0x0100,
		},
		EffectsMax: 0,
	}

	// 设置设备名称
	controllerInfo := pkg.ExtractControllerInfo(string(h.config.Name[:]))
	copy(usetup.Name[:], fmt.Sprintf("%s %d", controllerInfo.Name, h.deviceID))
	vendorNum, err := strconv.ParseUint(controllerInfo.Vendor, 16, 16)
	if err == nil {
		usetup.ID.Vendor = uint16(vendorNum)
	}
	productNum, err := strconv.ParseUint(controllerInfo.Product, 16, 16)
	if err == nil {
		usetup.ID.Product = uint16(productNum)
	}

	// 设置轴的范围
	for i := 0; i < int(h.config.NumAxes); i++ {
		usetup.Absmax[i] = 32767
		usetup.Absmin[i] = -32767
		usetup.Absfuzz[i] = 16
		usetup.Absflat[i] = 128
		// 修复十字键轴取值范围
		if h.config.AxesMap[i] == ABS_HAT0X || h.config.AxesMap[i] == ABS_HAT0Y {
			usetup.Absmax[i] = 1
			usetup.Absmin[i] = -1
			usetup.Absfuzz[i] = 0
			usetup.Absflat[i] = 0
		}
	}

	// 2. 写入设备信息
	if err := binary.Write(h.uinputFd, binary.LittleEndian, &usetup); err != nil {
		return fmt.Errorf("写入设备信息失败: %v", err)
	}

	// 3. 设置事件类型
	if err := pkg.IOctl(h.uinputFd, UI_SET_EVBIT, uintptr(EV_KEY)); err != nil {
		return fmt.Errorf("设置按键事件类型失败: %v", err)
	}
	if err := pkg.IOctl(h.uinputFd, UI_SET_EVBIT, uintptr(EV_ABS)); err != nil {
		return fmt.Errorf("设置轴事件类型失败: %v", err)
	}
	if err := pkg.IOctl(h.uinputFd, UI_SET_EVBIT, uintptr(EV_SYN)); err != nil {
		return fmt.Errorf("设置同步事件类型失败: %v", err)
	}

	// 4. 配置按钮
	logrus.Infof("正在配置 %d 个按钮...", h.config.NumBtns)
	for i := 0; i < int(h.config.NumBtns); i++ {
		btnCode := h.config.BtnMap[i]
		if err := pkg.IOctl(h.uinputFd, UI_SET_KEYBIT, uintptr(btnCode)); err != nil {
			return fmt.Errorf("配置按钮失败 (按钮索引: %d, 代码: 0x%x): %v", i, btnCode, err)
		}
		logrus.Debugf("配置按钮: 索引=%d, 代码=0x%x", i, btnCode)
	}

	// 5. 配置轴
	logrus.Infof("正在配置 %d 个轴...", h.config.NumAxes)
	for i := 0; i < int(h.config.NumAxes); i++ {
		axisCode := h.config.AxesMap[i]
		if err := pkg.IOctl(h.uinputFd, UI_SET_ABSBIT, uintptr(axisCode)); err != nil {
			return fmt.Errorf("配置轴失败 (轴索引: %d, 代码: 0x%x): %v", i, axisCode, err)
		}
		logrus.Debugf("配置轴: 索引=%d, 代码=0x%x", i, axisCode)
	}

	// 6. 最后创建设备
	if err := pkg.IOctl(h.uinputFd, UI_DEV_CREATE, 0); err != nil {
		return fmt.Errorf("创建设备失败: %v", err)
	}

	// 等待设备文件创建
	time.Sleep(2 * time.Second)

	// 创建设备后获取设备列表
	eventsAfter, _ := filepath.Glob("/dev/input/event*")
	joydevsAfter, _ := filepath.Glob("/dev/input/js*")

	// 找出新增的设备
	newEvents := pkg.FindNewDevices(eventsBefore, eventsAfter)
	newJoys := pkg.FindNewDevices(joydevsBefore, joydevsAfter)

	logrus.Infof("新创建的事件设备: %v", newEvents)
	logrus.Infof("新创建的游戏手柄设备: %v", newJoys)

	h.uinputCreated = true
	logrus.Infof("成功设置uinput设备: %s", strings.TrimRight(string(usetup.Name[:]), "\x00")) // 去掉字符串末尾的空字符
	return nil
}

// 4. 循环处理手柄事件
func (h *JoystickHandler) processEvents() error {
	buffer := make([]byte, 8) // IhBB = 4+2+1+1 = 8字节

	for {
		// 读取事件数据
		bLen, err := io.ReadFull(h.socketConn, buffer)
		if err != nil {
			logrus.Errorf("读取事件失败: %v", err)
			return fmt.Errorf("读取事件失败: %v", err) // 返回错以便在 boot 方法中处理
		}
		logrus.Debugf("读取事件: %d bytes", bLen)

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

		logrus.Debugf("等待下一个事件循环")
	}
}

// 4.1.转发事件到uinput设备
func (h *JoystickHandler) forwardEvent(event JoystickEvent) error {
	h.mu.Lock()
	defer h.mu.Unlock()

	eventType := event.Type & ^uint8(JS_EVENT_INIT)

	switch eventType {
	case JS_EVENT_BUTTON:
		// 获取映射的按钮代码
		if int(event.Number) >= int(h.config.NumBtns) {
			return fmt.Errorf("按钮编号-超出范围: %d", event.Number)
		}
		btnCode := h.config.BtnMap[event.Number]

		logrus.Debugf("转换为uinput按键事件.")
		// 转换为uinput按键事件
		err := h.writeUinputEvent(EV_KEY, btnCode, event.Value)
		if err != nil {
			return fmt.Errorf("按键事件-写入失败: %v", err)
		}
		logrus.Debugf("按钮触发: 原始编号=%d, 映射代码=0x%x, 值=%d", event.Number, btnCode, event.Value)

		// 发送同步事件
		err = h.writeUinputEvent(EV_SYN, 0, 0)
		if err != nil {
			return fmt.Errorf("同步事件-写入失败: %v", err)
		}
		logrus.Debugf("同步事件：写入成功.")
		return nil

	case JS_EVENT_AXIS:
		// 获取映射的轴代码
		if int(event.Number) >= int(h.config.NumAxes) {
			return fmt.Errorf("轴编号-超出范围: %d", event.Number)
		}
		axeCode := h.config.AxesMap[event.Number]

		// 修复 ABS_HAT0X 和 ABS_HAT0Y 的范围为 -1 到 1
		if axeCode == ABS_HAT0X || axeCode == ABS_HAT0Y {
			if event.Value < 0 {
				event.Value = -1
			} else if event.Value > 0 {
				event.Value = 1
			}
		}

		logrus.Debugf("轴触发: 原始编码=%d, 映射代码=0x%x, 值=%d", event.Number, axeCode, event.Value)

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

// 5. 释放资源
func (h *JoystickHandler) release() {
	h.mu.Lock()         // 锁定以确保线程安全
	defer h.mu.Unlock() // 解锁

	if h.socketConn != nil {
		h.socketConn.Close() // 关闭 socket 连接
		h.socketConn = nil   // 清空连接
		logrus.Infof("socket 连接已释放")
	}

	if h.uinputFd != nil {
		if h.uinputCreated {
			// 销毁 uinput 设备
			if err := pkg.IOctl(h.uinputFd, UI_DEV_DESTROY, 0); err != nil {
				logrus.Errorf("uinput 设备%d 销毁失败: %v", h.deviceID, err)
			} else {
				logrus.Infof("uinput 设备%d 已销毁", h.deviceID)
			}
			h.uinputCreated = false
		}
		h.uinputFd.Close() // 关闭 uinput 设备文件
		h.uinputFd = nil   // 清空文件描述符
		logrus.Infof("uinput 设备%d 已释放", h.deviceID)
	}

}

// 初始化日志
func initLogger() {
	// 使用 logrus 设置日志输出至控制台
	logrus.SetOutput(os.Stdout)
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

// NewJoystickHandler , 初始化一个动态的JoystickHandler
func NewJoystickHandler(socketPath string, index int) *JoystickHandler {
	return &JoystickHandler{
		config:     &JoystickConfig{}, // 初始化 config 字段
		socketPath: socketPath,        // 记录 socketPath
		deviceID:   index,             // 记录手柄索引
		isStable:   false,             // 是否稳定
	}
}

// NewJoystickHandlerStable , 初始化一个稳定的JoystickHandler
func NewJoystickHandlerStable(socketPath string, index int) *JoystickHandler {
	return &JoystickHandler{
		config:     &JoystickConfig{}, // 初始化 config 字段
		socketPath: socketPath,        // 记录 socketPath
		deviceID:   index,             // 记录手柄索引
		isStable:   true,              // 是否稳定
	}
}

// 创建处理器，传入 socketPath 和索引
var socketPaths = []string{
	"/tmp/selkies_js0.sock",
	"/tmp/selkies_js1.sock",
	"/tmp/selkies_js2.sock",
	"/tmp/selkies_js3.sock",
}

var handlers = make([]*JoystickHandler, len(socketPaths))

func main() {
	// 初始化日志
	initLogger()
	logrus.Infof("启动手柄事件转发服务")

	// 读取环境变量 BEAGLE-JOYSTICK-STABLE
	stableThreshold := os.Getenv("BEAGLE-JOYSTICK-STABLE")
	stableIndex, err := strconv.Atoi(stableThreshold)
	if err != nil {
		logrus.Debugf("环境变量 BEAGLE-JOYSTICK-STABLE 读取失败，使用默认值: %d", 0)
		stableIndex = 1 // 默认值
	}

	for i, socketPath := range socketPaths {
		var handler *JoystickHandler
		if i < stableIndex {
			handler = NewJoystickHandlerStable(socketPath, i) // 使用稳定模式
		} else {
			handler = NewJoystickHandler(socketPath, i) // 使用普通模式
		}
		handlers[i] = handler
		go handler.boot() // 启动每个处理器
	}

	// 阻塞主线程，直到所有处理器完成
	select {}
}

func release() {
	for _, handler := range handlers {
		handler.release()
	}

	// 退出程序，状态码1表示异常退出
	logrus.Info("程序即将退出...")
	os.Exit(1)
}
