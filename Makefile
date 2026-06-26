.PHONY: all build run dmg clean

all: build

build:
	./scripts/build.sh

run:
	swift run comux

dmg:
	./scripts/dmg.sh

clean:
	rm -rf .build build dist
