package main

import "os"

func touch(path string) bool {
	_, err := os.Stat(path)
	if err == nil {
		return true
	}
	file, err := os.Create(path)
	if err == nil{
		file.Close()
		return true
	}
	return false
}
