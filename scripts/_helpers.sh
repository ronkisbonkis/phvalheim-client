#!/bin/bash

get_version() {
    ROOT=$1
    # Get the version from the csproj
    VERSION=$(grep -oPm1 "(?<=<Version>)[^<]+" $ROOT/phvalheim-client.csproj)

    # Get the major, minor and patch version
    MAJOR=$(echo $VERSION | cut -d"." -f1)
    MINOR=$(echo $VERSION | cut -d"." -f2)
    PATCH=$(echo $VERSION | cut -d"." -f3)

    echo "$MAJOR.$MINOR.$PATCH"
}

generate_changelog() {
    ROOT=$1
    # make sure jq is installed
    if ! command -v jq &>/dev/null; then
        echo "jq could not be found"
        exit
    fi

    # make sure curl is installed
    if ! command -v curl &>/dev/null; then
        echo "curl could not be found"
        exit
    fi

    # make sure ../debian exists
    if [ ! -f $ROOT/debian ]; then
        mkdir -p $ROOT/debian
    fi

    # Get all releases from github
    RELEASES=$(curl -s https://api.github.com/repos/brianmiller/phvalheim-client/releases)

    # Delete the changelog if it exists
    if [ -f $ROOT/debian/changelog ]; then
        rm $ROOT/debian/changelog
    fi

    # For each realease, get the tag name, body, author, date and seperate the version into major, minor and patch
    for release in $(echo $RELEASES | jq -r '.[] | @base64'); do
        _jq() {
            echo ${release} | base64 --decode | jq -r ${1}
        }

        TAG_NAME=$(_jq '.tag_name')
        BODY=$(_jq '.body')
        AUTHOR=$(_jq '.author.login')
        EMAIL=$(_jq '.author.html_url')
        DATE=$(_jq '.published_at')

        # Format the date like this: Wed, 21 Oct 2015 07:28:00 -0700
        DATE=$(date -d $DATE +"%a, %d %b %Y %H:%M:%S %z")

        # Write the changelog to ../debian/changelog
        echo "phvalheim-client ($TAG_NAME) stable; urgency=low" >>$ROOT/debian/changelog
        echo "" >>$ROOT/debian/changelog

        # For each line in the body, remove whitespace from beginning and end of line
        # if line is not empty, and line is less than 80 characters, and the previous line was empty, then add the line to the changelog enclosed in []
        # otherwise, add the line as a bullet point
        while IFS= read -r line; do
            line=$(echo $line | sed 's/^[[:space:]]*//g' | sed 's/[[:space:]]*$//g')
            if [ ! -z "$line" ]; then
                if [ ! -z "$line" ] && [ ${#line} -lt 80 ] && ([ -z "$prev_line" ] || [ -z "$prev_line" ] || [ -z "$prev_line" ]); then
                    echo "  [$line]" >>$ROOT/debian/changelog
                else
                    echo "  *  $line" >>$ROOT/debian/changelog
                fi
            fi
            prev_line=$line
        done <<<"$BODY"

        echo "" >>$ROOT/debian/changelog
        echo " -- $AUTHOR <$EMAIL>  $DATE" >>$ROOT/debian/changelog
        echo "" >>$ROOT/debian/changelog
    done
}

generate_control() {
    ROOT=$1
    # make sure the debian folder exists
    if [ ! -f $ROOT/debian ]; then
        mkdir -p $ROOT/debian
    fi

    # Create a minimal control file from the csproj and github api
    echo "Source: phvalheim-client
Section: games
Priority: optional
Maintainer: Brian Miller <>

Package: phvalheim-client
Architecture: amd64
Depends: \${shlibs:Depends}, \${misc:Depends}
Description: A x-url-handler for PhValheim
" >$ROOT/debian/control
}

generate_rules() {
    ROOT=$1

    # make sure the debian folder exists
    if [ ! -f $ROOT/debian ]; then
        mkdir -p $ROOT/debian
    fi

    echo "#!/usr/bin/make -f
# Uncomment this to turn on verbose mode.
#export DH_VERBOSE=1

%: 
	dh \$@

override_dh_auto_build:
	dotnet publish \
		-c Release \
        -r linux-x64 \
        -p:PublishSingleFile=true \
        --self-contained true \
        ./phvalheim-client.csproj \
        /property:GenerateFullPaths=true \
        /consoleloggerparameters:NoSummary \
		/p:PublishTrimmed=false \

override_dh_auto_install:
	mkdir -p \$(CURDIR)/debian/phvalheim-client/usr/bin
	cp -r \$(CURDIR)/bin/Release/net6.0/linux-x64/publish/phvalheim-client \$(CURDIR)/debian/phvalheim-client/usr/bin
	mkdir -p \$(CURDIR)/debian/phvalheim-client/usr/share/applications
	cp -r \$(CURDIR)/debian/phvalheim.desktop \$(CURDIR)/debian/phvalheim-client/usr/share/applications

override_dh_strip:
	dh_strip --exclude=phvalheim-client
	" >$ROOT/debian/rules
}

generate_postinst() {
    ROOT=$1

    # make sure the debian folder exists
    if [ ! -f $ROOT/debian ]; then
        mkdir -p $ROOT/debian
    fi

    # Create a minimal postinst file
    echo "#!/bin/sh
set -e

if [ \"$1\" = \"configure\" ]; then
  update-desktop-database -q
  gio mime x-scheme-handler/phvalheim phvalheim.desktop
fi
" >$ROOT/debian/postinst

    # Make sure path exists
    mkdir -p $ROOT/debian/phvalheim-client/usr/share/applications

    # Add a .Desktop file for the x-url-handler
    echo "[Desktop Entry]
Name=PhValheim-Client
Comment=PhValheim-Client
Exec=/usr/bin/phvalheim-client %U
Terminal=true
Type=Application
MimeType=x-scheme-handler/phvalheim;
" >$ROOT/debian/phvalheim.desktop
}
