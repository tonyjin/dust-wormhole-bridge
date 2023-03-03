include testing.env

.PHONY: all test unit-test integration-test build dependencies clean

all: build

test: unit-test integration-test

unit-test:
	cargo clippy -- --allow clippy::result_large_err
	cargo test

integration-test: dependencies
	anchor test

build: dependencies
	anchor build

dependencies:
	yarn
	$(MAKE) -C dependencies

clean:
	$(MAKE) -C dependencies clean
	rm -rf node_modules target .anchor
