.PHONY: bump_build build run

bump:
	@cur=$$(grep 'version:' pubspec.yaml | cut -d '+' -f2); \
	new=$$(($$cur + 1)); \
	sed -i "s/\+$$cur/\+$$new/" pubspec.yaml; \
	echo "Build $$cur -> $$new"

build: bump
	flutter build apk

run: bump
	flutter run
