.PHONY: all build run dmg release clean

all: build

build:
	./scripts/build.sh

run:
	swift run comux

dmg:
	./scripts/dmg.sh

release:
	./scripts/release-cli.sh $(ARGS)

clean:
	rm -rf .build build dist
