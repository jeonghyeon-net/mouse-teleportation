.PHONY: build test check live-check install uninstall package release-prepare release status
build:
	python3 scripts/project.py build
test:
	python3 scripts/project.py test
check:
	python3 scripts/project.py check
live-check:
	swift scripts/live-check.swift
install:
	python3 scripts/project.py install
uninstall:
	python3 scripts/project.py uninstall
package:
	python3 scripts/project.py package
release-prepare:
	python3 scripts/project.py prepare
release:
	python3 scripts/project.py release
status:
	"/Applications/Mouse Teleportation.app/Contents/MacOS/MouseTeleportation" --status
