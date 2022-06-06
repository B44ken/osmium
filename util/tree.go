// terminal file browser
// should have some fun features because for now it's just a glorifed `find .`

package main;
import (
	"io/ioutil"
)

func tree(dir string) string {
	return makeTree(dir, "", "")
}

func makeTree(dir, buffer, prepend string) string {
	buffer = ""
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		panic(err)
	}
	for _, f := range files {
		if f.Name()[0] == '.' { continue }
		if f.IsDir() {
			buffer += prepend + f.Name() + "/\n"
			buffer += makeTree(dir + "/" + f.Name(), buffer, prepend + ". ")
		} else {
			buffer += prepend + f.Name() + "\n";
		}
	}
	return buffer
}
