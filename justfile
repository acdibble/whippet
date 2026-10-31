project := "Whippet.xcodeproj"
scheme := "Whippet"
destination := "platform=macOS"
dev_app := "Whippet Dev"
dev_build := "build/dev"

# Lists the recipes.
default:
    @just --list --unsorted

# Regenerates the Xcode project, which isn't committed, from project.yml.
generate:
    xcodegen generate --quiet

# Builds Whippet Dev, the Debug app that runs beside an installed release.
build: generate
    xcodebuild build -project {{project}} -scheme {{scheme}} -configuration Debug -destination '{{destination}}' \
        -derivedDataPath {{dev_build}}

# Builds Whippet Dev, quits the running copy and opens the new one.
run: build stop
    open "{{dev_build}}/Build/Products/Debug/{{dev_app}}.app"

# Quits Whippet Dev.
stop:
    -@pkill -x "{{dev_app}}"
    @# Waits for it to exit, so `open` launches the new build instead of reactivating the old one.
    @while pgrep -x "{{dev_app}}" > /dev/null; do sleep 0.1; done

# Runs the tests without signing, as CI does, or one suite or test, e.g. `UnitConversionTests/rates`.
test filter="": generate
    xcodebuild test -project {{project}} -scheme {{scheme}} -destination '{{destination}}' CODE_SIGNING_ALLOWED=NO \
        {{ if filter == "" { "" } else { "-only-testing:WhippetTests/" + filter } }}

# Formats the Swift sources in place with swift-format, which comes with Xcode, using `.swift-format`.
format:
    git ls-files -z '*.swift' | xargs -0 xcrun swift-format format --in-place --parallel

# Checks the Swift sources' formatting and style without changing them, as CI does.
lint:
    git ls-files -z '*.swift' | xargs -0 xcrun swift-format lint --strict --parallel

# Opens the project in Xcode.
open: generate
    open {{project}}

# Removes the build output and the generated project.
clean:
    rm -rf build {{project}}
