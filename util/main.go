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
			treeOut := tree(os.Args[argi+1])
			fmt.Println(treeOut)
		} else if command == "" && arg == "file" {
			command = arg
		}
	}
	if command == "" {
		fmt.Println("no commands found (one of tree, file)")
	}
}
