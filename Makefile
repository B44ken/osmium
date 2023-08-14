run: native
	cd build
	./osmium
	cd ..

native:
	g++ src/main.cpp src/*/*.cpp -std=c++20 -lSDL2main -lSDL2 -lSDL2_ttf -Wall -o build/osmium

mingw:
	g++ src/main.cpp src/*/*.cpp -lmingw32 -lSDL2main -lSDL2 -lSDL2_ttf -I'/c/mingw_dev_lib/include/' -L'/c/mingw_dev_lib/lib' -Wall -o build/osmium.exe

	# x86_64-w64-mingw32-g++ src/*.cpp \
	# -I'/mnt/c/mingw_dev_lib/include/' -L'/mnt/c/mingw_dev_lib/lib' \
	# -lmingw32 -lSDL2main -lSDL2 -lSDL2_ttf \
	# -o build/osmium.exe


run-mingw: mingw
	cd build
	./osmium.exe
	cd ..

delete:
	rm build/osmium*