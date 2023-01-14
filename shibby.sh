#!/usr/bin/env bash
#       __   _ __   __
#  ___ / /  (_) /  / /  __ __
# (_-</ _ \/ / _ \/ _ \/ // /
#/___/_//_/_/_.__/_.__/\_, /
#                     /___/

########################################
#######       GLOBAL VARS        #######
########################################
version="1.0.0"
scriptName="shibby"
scriptPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SVC_ENDPOINT="https://sentry-read.svc.overdrive.com"
THUNDER_ENDPOINT="https://thunder.api.overdrive.com"
D_COOKIE=""
SSCL_COOKIE=""
TOKEN_PATH="./token.id"
syncPayload=""

########################################
#######           UTIL           #######
########################################
# These shared utilities provide many functions which are needed to provide
# the functionality in this script
#utilsLocation="${scriptPath}/lib/utils.sh" # Update this path to find the utilities.

getToken() {
  local chipPayload
  # Requests a brand new token, extracts the value, and stores it in the identity file
  chipPayload=$(curl -X POST -f -s $SVC_ENDPOINT"/chip" && echo "" || echo "Could not retrieve token.")
  getIdentityPayload "$chipPayload"
}

#TODO: combine common curl arguments into a variable
#TODO: combine common jq arguments into a variable

getSecondToken() {
  local chipPayload
  local tokenValue
  echo "getting second token"
  # if file is not empty
  if [ -s $TOKEN_PATH ];
  then
    tokenValue=$(cat "$TOKEN_PATH")
    chipPayload=$(curl -H "Accept: application/json" -H "Authorization: Bearer $tokenValue" -X POST -f -s $SVC_ENDPOINT"/chip")
    getIdentityPayload "$chipPayload"
  else
    echo "Unknown token"
  fi
}

getIdentityPayload() {
  local arg1
  local identity
  arg1=$1
  # first grep gets everything after 'identity' until a comma is found
  # second grep grabs everything from the colon to the end of the string
  # the sed removes the quotes
  # TODO: Create the token file if the path is empty
  identity=$(echo "$arg1" | grep -Eo '"identity"[^,]*' | grep -Eo '[^:]*$' | sed -e 's/^"//' -e 's/"$//')
  printf "$identity" > $TOKEN_PATH
}

syncWithLibby() {
  local code
  local JSON_TMP
  local JSON
  local clonePayload
  local tokenValue
  code=$1
  tokenValue=$(cat "$TOKEN_PATH")
  JSON_TMP='{"code": "%s"}\n'
  JSON=$(printf "$JSON_TMP" "$code")
  clonePayload=$(curl -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $tokenValue" -d "$JSON" -X POST -f -s $SVC_ENDPOINT"/chip/clone/code" && echo "" || echo "Code sync didn't work")
  echo "$clonePayload"
}

printLibraries() {
  getSyncPayload
  echo "$syncPayload" | jq -r '"Library:CardId", "------:------", (.cards[] | .library.name + ":" + .cardId)' | column -s: -t
  #TODO: find a better way to generate a table with headers
}

getSyncPayload() {
  local tokenValue
  if [ -s $TOKEN_PATH ];
  then
    tokenValue=$(cat "$TOKEN_PATH")
    syncPayload=$(curl -H "Accept: application/json" -H "Authorization: Bearer $tokenValue" -X GET -f -s $SVC_ENDPOINT"/chip/sync")
  else
    echo "Missing token, be sure to resync and authenticate with a libby code"
  fi
}

checkout() {
  local cardId
  local bookId
  local libraryName
  local loanPayload
  local tokenValue
  local expireDate
  cardId=$1
  bookId=$2
  tokenValue=$(cat "$TOKEN_PATH")
  getSyncPayload
  libraryName=$(echo "$syncPayload" | jq --arg foo "$cardId" -r '(.cards[] | select(.cardId==$foo)) | .library.name')
  # TODO throw an error if the cardId isn't recognized (pull the list of cards and compare it to the input)
  echo "Checking out book from $libraryName...."
  loanPayload=$(curl -H "Accept: application/json" -H "Authorization: Bearer $tokenValue" -X POST -f -s $SVC_ENDPOINT"/card/$cardId/loan/$bookId")
  expireDate=$(echo "$loanPayload" | jq -r '.expireDate')
  if [ -n "$expireDate" ]; then
    local titleAndAuthor
    titleAndAuthor=$(echo "$loanPayload" | jq -r '.title + " by " + .firstCreatorName')
    echo "Successfully checked out $titleAndAuthor from $libraryName. It is due back on $expireDate"
  # TODO make the date look better
  else
    echo "Something went wrong during checkout. Server responded with the following..."
    echo "$loanPayload"
  fi
}

setUpDownloadPath() {
  # if the download path option isn't provided, set a default location
  if [ -z "$DOWNLOAD_PATH" ]; then
    echo "No download path provided -- will save the audiobook to ~/audiobooks"
    DOWNLOAD_PATH="$HOME/audiobooks"
  fi

  # if the mkdir command fails, return an error
  if ! mkdir -p "$DOWNLOAD_PATH" 2>/dev/null; then
    echo "Can't create or access the download location $DOWNLOAD_PATH. Please ensure you have write permissions in this area."
    exit
  fi
}

download() {
  # TODO, throw an error if the book id is not an audiobook
  local cardId
  local bookId
  local audiobookPayload
  local tokenValue
  local message
  local webUrl
  local openbookUrl
  local openbookPayload
  local libraryName
  local libbyAppHeaders
  local cookieTmp
  cardId=$1
  bookId=$2
  tokenValue=$(cat "$TOKEN_PATH")
  getSyncPayload
  libraryName=$(echo "$syncPayload" | jq --arg foo "$cardId" -r '(.cards[] | select(.cardId==$foo)) | .library.name')
  # TODO throw an error if the cardId isn't recognized (pull the list of cards and compare it to the input)
  # TODO throw an error if the bookId isn't checked out at the library provided
  echo "Downloading the book from $libraryName...."

  # retrieve message, urls.web and urls.openbook values
  audiobookPayload=$(curl -H "Accept: application/json" -H "Authorization: Bearer $tokenValue" -X GET -f -s $SVC_ENDPOINT"/open/audiobook/card/$cardId/title/$bookId")
  webUrl=$(echo "$audiobookPayload" | jq -r '.urls.web')
  message=$(echo "$audiobookPayload" | jq -r '.message')
  openbookUrl=$(echo "$audiobookPayload" | jq -r '.urls.openbook')

  # HEAD to https://URL_WEB_VALUE/?m=MESSAGE_VALUE
  libbyAppHeaders=$(curl -H "Authorization: Bearer $tokenValue" -I HEAD -f -s "$webUrl?$message")

  # retrieve values from response header, 'd' and '_sscl_d'
  # couldn't get regex to work, but this would be the pattern (?<=Set-Cookie: _sscl_d=).*?(?=;)
  local commonEnding="; path=" # substring to find the end of the cookie value
  local dCookieSearch="set-cookie: d=" # substring to find the d cookie
  cookieTmp=$(echo "$libbyAppHeaders" | grep "$dCookieSearch")
  D_COOKIE="${cookieTmp#*"${dCookieSearch}"}" # trim through the cookie with the search pattern from the front (left)
  D_COOKIE="${D_COOKIE%"${commonEnding}"*}" # add header key (d) and trim through common ending from the back (right)

  # now do the same for the sscl header
  local ssclCookieSearch="set-cookie: _sscl_d=" # substring to find the sscl cookie
  cookieTmp=$(echo "$libbyAppHeaders" | grep "$ssclCookieSearch")
  SSCL_COOKIE="${cookieTmp#*"${ssclCookieSearch}"}"
  SSCL_COOKIE="${SSCL_COOKIE%"${commonEnding}"*}"

  # GET to urls.openbook with all cookies (bearer, d, and sscl)
  # PROPER FORMAT FOR THE HEADER IS "Cookie: _sscl_d=COOKIE_VALUE; d=COOKIE_VALUE"
  openbookPayload=$(curl -H "Accept: application/json" -H "Authorization: Bearer $tokenValue" -H "Cookie: _sscl_d=$SSCL_COOKIE; d=$D_COOKIE" -X GET -f -s "$openbookUrl" )

  # get the author and book name without spaces to use in the directory path to the mp3 files
  bookName=$(echo "$openbookPayload" | jq -r '.title.main' | tr -d ' ')
  authorName=$(echo "$openbookPayload" | jq -r '.creator[] | select(.role == "author").name' | tr -d ' ')

  presentDirectory=$(pwd)
  cd "$DOWNLOAD_PATH"
  mkdir -p ./"$authorName"/"$bookName"
  cd "$authorName"/"$bookName"
  # parts to download will be in the spine.path objects. Store these in a file for looping over later.
  # TODO, could potentially avoid writing to the file and put these directly in an array but I ran into issues doing this
  local tmpPath="./tmpParts.txt"
  echo "$openbookPayload" | jq -r '.spine[].path' > $tmpPath

  # For each line (book part path), sent a GET to the WEB_URL/path value with all the appropriate cookies.
  iter=0
  while IFS= read -r line; do
  ((iter=iter+1))
  printf '%s\r\n' "Downloading part $iter...."
  # To get the files, query the web url followed by the path value (the line value in this case)
  # -o downloads the file and gives it a local name we provide
  # -L follows the redirect to odrmediaclips.cachefly.net
  curl -o "part$iter.mp3" -L -f -s -H "Accept: */*" -H "Authorization: Bearer $tokenValue" -H "Cookie: _sscl_d=$SSCL_COOKIE; d=$D_COOKIE" -X GET "$webUrl"/"$line"
  done < "$tmpPath"

  # delete the tmp file
  if test -f $tmpPath; then
    rm $tmpPath
  fi
  # move back to our original directory
  cd "$presentDirectory"
  # TODO Failure message if the download didn't work
  # TODO Provide a way for the user to determine where the download will go
}

########################################
#######          FLAGS           #######
########################################
# Flags which can be overridden by user input.
# Default values are below
downloadBook=0
checkoutBook=0
auth=0
list=0
resync=0
strict=0
debug=0

########################################
#######           MAIN           #######
########################################
function mainScript() {
  # TODO: add if statement for the checkout path
  if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Please install jq by following the instructions here https://stedolan.github.io/jq/download/"
    exit
  fi

  # downloading a book
  if [ $downloadBook == 1 ]; then
    local cardId
    local bookId
    setUpDownloadPath
    echo "Enter Library Card: "; read -r cardId; echo "Enter Book Id: "; read -r bookId; echo
    # TODO combine the library card entry between the download and checkout into a common function that sets a global var
    if [ "$cardId" != "" ] && [ "$bookId" != "" ]; then
      download "$cardId" "$bookId"
    else echo "Both cardId and bookId must have a value"
    fi
  fi

  # checking out a book
  if [ $checkoutBook == 1 ]; then
    local cardId
    local bookId
    echo "Enter Library Card: "; read -r cardId; echo "Enter Book Id: "; read -r bookId; echo
    if [ "$cardId" != "" ] && [ "$bookId" != "" ]; then
      checkout "$cardId" "$bookId"
    else echo "Both cardId and bookId must have a value"
    fi
  fi

  # listing out the libraries
  if [ $list == 1 ]; then
    printLibraries
    exit
  fi

  # if resync flag is passed, we need to get a token and then exit.
  # other housekeeping/setup stuff can go here
  if [ $resync == 1 ]; then
    echo "resyncing...requesting a new token and writing it to the token.id file"
    getToken
    exit
  fi

  # if the token file is empty, request a new token
  if [ ! -s $TOKEN_PATH ]; then
    echo "no token found, requesting one and writing it to the token.id file"
    getToken
  fi

  # if authorizing, we want to simply sync with the provided code, update our bearer token, and then exit as nothing else is needed.
  if [ $auth == 1 ]; then
    echo "authorizing with code $authCode"
    syncWithLibby "$authCode"
    getSecondToken
    exit
  fi
# TODO: Better error handling if the requests don't work

############### End Script Here ####################
}

########################################
#######        HELP TEXT         #######
########################################
usage() {
  echo -n "${scriptName} [OPTION]...
 Options:
  -a, --auth [AUTH CODE]  Login with numeric code generated from Libby app
  -r, --resync            Start here! Force a new token retrieval (sometimes needed as previously provided tokens can expire)
  -c, --checkout          Checkout a book. You will be prompted for the library card id (use the --list command to see these) and the book id (get this from the overdrive website URL)
  -d [PATH]               Downloads the audiobook to the location provided as an argument. You will be prompted for the library card and the book id to download.
  --list                  Shows all your libraries and the respective card Ids
  --debug                 Runs script in BASH debug mode (set -x)
  -h, --help              Display this help and exit
  --version               Output version information and exit
"
}

# Iterate over options breaking -ab into -a -b when needed and --foo=bar into
# --foo bar
optstring=h
unset options
while (($#)); do
  case $1 in
    # If option is of type -ab
    -[!-]?*)
      # Loop over each character starting with the second
      for ((i=1; i < ${#1}; i++)); do
        c=${1:i:1}

        # Add current char to options
        options+=("-$c")

        # If option takes a required argument, and it's not the last char make
        # the rest of the string its argument
        if [[ $optstring = *"$c:"* && ${1:i+1} ]]; then
          options+=("${1:i+1}")
          break
        fi
      done
      ;;

    # If option is of type --foo=bar
    --?*=*) options+=("${1%%=*}" "${1#*=}") ;;
    # add --endopts for --
    --) options+=(--endopts) ;;
    # Otherwise, nothing special
    *) options+=("$1") ;;
  esac
  shift
done
set -- "${options[@]}"
unset options

# Print help if no arguments were passed.
[[ $# -eq 0 ]] && set -- "--help"

# Read options
while [[ $1 = -?* ]]; do
  case $1 in
    -h|--help) usage >&2; exit ;;
    --version) echo "$(basename $0) ${version}"; exit ;;
    -r|--resync) resync=1 ;;
    -a|--auth) shift; authCode=${1}; auth=1 ;;
    -c|--checkout) checkoutBook=1 ;;
    -d) shift; DOWNLOAD_PATH=${1}; downloadBook=1 ;;
    --list) list=1 ;;
    --debug) debug=1 ;;
    --endopts) shift; break ;;
    *) echo "invalid option: '$1' Use -h or --help to view list of options."
      exit;;
  esac
  shift
done

# Store the remaining part as arguments.
args+=("$@")

############# ############# #############
##       TIME TO RUN THE SCRIPT        ##
############# ############# #############

# Exit on error. Append '||true' when you run the script if you expect an error.
set -o errexit

# Run in debug mode, if set
if [ "${debug}" == "1" ]; then
  set -x
fi

# Exit on empty variable
if [ "${strict}" == "1" ]; then
  set -o nounset
fi

# Bash will remember & return the highest exitcode in a chain of pipes.
# This way you can catch the error in case mysqldump fails in `mysqldump |gzip`, for example.
set -o pipefail

# Run your script
mainScript