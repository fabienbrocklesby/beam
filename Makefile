.PHONY: ghostty app debug run format lint test check bench launch dmg clean

SWIFT_PATHS = Package.swift Sources Tests scripts

# libghostty from the pinned submodule. Slow (minutes); only needed after a bump.
ghostty:
	scripts/build-ghostty.sh

app:
	scripts/bundle.sh release

debug:
	scripts/bundle.sh debug

run: app
	build/Beam.app/Contents/MacOS/Beam

format:
	swift format format --in-place --recursive --parallel $(SWIFT_PATHS)

lint:
	swift format lint --strict --recursive --parallel $(SWIFT_PATHS)
	scripts/lint-text.sh

# Warnings are errors for every target (see Package.swift).
test:
	swift test

# Everything a commit must pass. The pre-commit hook runs the fast half.
check: lint test app
	scripts/budget.sh

bench: app
	scripts/bench.sh

launch: app
	scripts/launch.sh

# build/Beam-<version>.dmg: the app and an Applications link, laid out.
dmg: app
	scripts/dmg.sh

clean:
	rm -rf .build build
