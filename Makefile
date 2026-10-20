.PHONY: app build checks clean dmg docs-check docs-impact icon open release run

build:
	swift build

release:
	swift build -c release

run:
	swift run PacManArcade

checks:
	swift run PacManChecks

docs-check:
	python3 scripts/check_docs.py

docs-impact:
	python3 scripts/check_docs.py --changed

app:
	./scripts/build_app.sh

open: app
	open dist/PAC-MAN.app

dmg: app
	hdiutil create -volname "PAC-MAN" -srcfolder "dist/PAC-MAN.app" -ov -format UDZO "dist/PAC-MAN-1.0.dmg"

icon:
	python3 scripts/make_icon.py

clean:
	swift package clean
	rm -rf dist
