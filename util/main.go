package main

import (
	"os"
	"fmt"
)

func main() {
	command := ""
	for argi, arg := range os.Args {
		if command == "" && arg == "tree" {
			command = arg
			if argi+1 == len(os.Args) {
				fmt.Println(tree("."))
			} else {
				path := os.Args[argi]
				fmt.Println(tree(path))
			}
			os.Exit(0)
		} else if command == "" && arg == "touch" {
			if argi + 1 == len(os.Args) {
				fmt.Println("touch needs an argument")
				os.Exit(2)
			}
			path := os.Args[argi + 1]
			if touch(path) {
				os.Exit(0)
			}
			os.Exit(1)
		}
	}
	fmt.Println("no commands found (one of tree, touch)")
}
