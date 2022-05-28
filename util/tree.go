// terminal file browser
// should have some fun features because for now it's just a glorifed `find .`

package main;
import (
	"fmt"
	"io/ioutil"
)

func main() {
	tree := printDir(".", "")
	fmt.Println(tree)
}

func printDir(dir string, buffer string) string {
	buffer = ""
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		panic(err)
	}
	for _, f := range files {
		if f.Name()[0] == '.' { continue }
		if f.IsDir() {
			buffer += printDir(dir + "/" + f.Name(), buffer)
		} else {
			buffer += dir + "/" + f.Name() + "\n"
		}
	}
	return buffer
}