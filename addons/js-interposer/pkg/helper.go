package pkg

import (
	"os"
	"regexp"
	"strings"
	"syscall"
)

type ControllerInfo struct {
	Name    string
	Vendor  string
	Product string
}

func ExtractControllerInfo(input string) ControllerInfo {
	// 先去除所有 null 字符
	cleanName := strings.TrimRight(input, "\x00")

	// 正则表达式提取手柄名称、Vendor和Product编号
	re := regexp.MustCompile(`^(.*?)\s*(?:\((?:.*?Vendor:\s*(\w+)\s*Product:\s*(\w+))\))?$`)
	matches := re.FindStringSubmatch(cleanName)

	var name, vendor, product string
	if len(matches) > 1 {
		name = strings.TrimSpace(matches[1]) // 提取手柄名称并去掉多余空格
	}
	if len(matches) > 3 {
		vendor = matches[2]  // 提取Vendor编号
		product = matches[3] // 提取Product编号
	}

	return ControllerInfo{Name: name, Vendor: vendor, Product: product}
}

// 辅助函数：找出新增设备
func FindNewDevices(before, after []string) []string {
	existing := make(map[string]bool)
	for _, dev := range before {
		existing[dev] = true
	}

	var newDevices []string
	for _, dev := range after {
		if !existing[dev] {
			newDevices = append(newDevices, dev)
		}
	}
	return newDevices
}

func IOctl(fd *os.File, request, arg uintptr) error {
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd.Fd(), request, arg)
	if errno != 0 {
		return errno
	}
	return nil
}