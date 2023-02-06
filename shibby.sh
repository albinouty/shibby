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
THUNDER_ENDPOINT="https://thunder.api.overdrive.com/v2"
OVERDRIVE_DATE_FORMAT="%Y-%m-%dT%H:%M:%SZ"
SHIBBY_DATE_FORMAT="+%A, %_d %B %Y at %r %Z"
D_COOKIE=""
SSCL_COOKIE=""
TOKEN_PATH="./token.id"
syncPayload=""
bookInfo=""
SUPPORTED_FORMAT="audiobook"
TMP_DIR=./shibbyTmp # directory to store tmp information. Deleted at beginning and end of certain calls should things go wrong.
listLength=0
formatCharacters="\r\n" # carriage return plus new line. Can use "echo -e" if the results look weird with this.
formattedDate=""

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
  identity=$(echo "$arg1" | jq -r '.identity')
  printf "$identity" > $TOKEN_PATH
}

getBookInfo() {
  local bookId
  bookId=$1
  bookInfo=$(curl -f -s -H "Accept: application/json" -X GET $THUNDER_ENDPOINT"/media/$bookId")
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
  echo "$syncPayload" | jq -r '"Library:CardId:Libby Key", "---------:---------:---------", (.cards[] | .library.name + ":" + .cardId + ":" + .advantageKey)' | column -s: -t
  #TODO: find a better way to generate a table with headers
}

libraryIdLookup() {
  local library=$1
  local id
  id=$(echo "$syncPayload" | jq --arg foo "$library" -r '(.cards[] | select(.advantageKey==$foo)) | .cardId')
}

checkIfValidCardId() {
  local cardId=$1
  local cards=$(echo "$syncPayload" | jq -r '[.cards[].cardId] | join(",")')
  IFS=',' read -r -a cardArray <<< "$cards"
  if [[ ! " ${cardArray[*]} " == *"$cardId"* ]]; then
    echo "$cardId is not a card associated with your account. The cards you have are..."
    printLibraries
    exit
  fi
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

formatDate() {
# date passed in must be in the format of OVERDRIVE_DATE_FORMAT or this will not work
  theDate=$1
  formattedDate=$(date -jf "$OVERDRIVE_DATE_FORMAT" "$theDate" "$SHIBBY_DATE_FORMAT" 2> /dev/null || date date -d "$theDate" "$SHIBBY_DATE_FORMAT" 2> /dev/null)
}

checkout() {
  # TODO, unable to checkout a book if it is available from a hold
  # TODO, no error is thrown if the book does not check out
  local cardId
  local bookId
  local libraryName
  local loanPayload
  local tokenValue
  local expireDate
  cardId=$1
  bookId=$2
  getBookInfo "$bookId"
  bookName=$(echo "$bookInfo" | jq -r '.title')
  tokenValue=$(cat "$TOKEN_PATH")
  libraryName=$(echo "$syncPayload" | jq --arg foo "$cardId" -r '(.cards[] | select(.cardId==$foo)) | .library.name')
  echo "Checking out $bookName from $libraryName...."
  loanPayload=$(curl -H "Accept: application/json" -H "Authorization: Bearer $tokenValue" -X POST -f -s $SVC_ENDPOINT"/card/$cardId/loan/$bookId")
  expireDate=$(echo "$loanPayload" | jq -r '.expireDate')
  if [ -n "$expireDate" ]; then
    local titleAndAuthor
    titleAndAuthor=$(echo "$loanPayload" | jq -r '.title + " by " + .firstCreatorName')
    # format the date for both macs and linux date functions. It'll pick whatever one can run.
    formatDate $expireDate
    echo "Successfully checked out $titleAndAuthor from $libraryName. It is due back on $formattedDate"
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
  getBookInfo "$bookId"
  bookName=$(echo "$bookInfo" | jq -r '.title')
  authorName=$(echo "$bookInfo" | jq -r '.firstCreatorName')
  media=$(echo "$bookInfo" | jq -r '.type.id')
  if [ ! "$media" == "$SUPPORTED_FORMAT"  ]; then
    echo "The bookId $bookId ($bookName) is not an audiobook and cannot be downloaded by shibby at this time..."
    exit
  fi
  libraryName=$(echo "$syncPayload" | jq --arg foo "$cardId" -r '(.cards[] | select(.cardId==$foo)) | .library.name')
  cardThatOwnsBook=$(echo "$syncPayload" | jq --arg foo "$bookId" -r '.loans[] | select(.id==$foo) | .cardId')
  # check if book is checked out at this library
  if [ ! "$cardId" == "$cardThatOwnsBook" ]; then
    echo "ERROR: The book \"$bookName\" is not checked out at $libraryName ($cardId). Exiting..."
    exit
  fi
  # TODO throw an error if the bookId isn't checked out at the library provided
  echo "Downloading $bookName from $libraryName...."

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
  bookNameNoSpaces=$(echo "$bookName" | tr -d ' ')
  authorNameNoSpaces=$(echo "$authorName" | tr -d ' ')

  presentDirectory=$(pwd)
  cd "$DOWNLOAD_PATH"
  mkdir -p ./"$authorNameNoSpaces"/"$bookNameNoSpaces"
  cd "$authorNameNoSpaces"/"$bookNameNoSpaces"
  echo "Downloading cover"
  coverLocation=$(echo "$bookInfo" | jq -r '.covers.cover510Wide.href' | sed -e "s/{/%7B/" -e "s/}/%7D/")
  curl -o "cover.jpg" -f -s "$coverLocation"

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
}

getListLength() {
  local path
  path=$1
  listLength=$(jq -r 'length' $path)
  echo "Found $listLength books..."
}

printLoans() {
  local TMP_LOANS=$TMP_DIR/loans.txt
  local TMP_INDV_LOAN=$TMP_DIR/individualLoan.txt
  local allResults="Title_Author_BookId_Publisher_Duration_Library / Id_Due Date${formatCharacters}" # these are the headers for the loans
  mkdir -p $TMP_DIR
  getSyncPayload
  echo "$syncPayload" | jq -r '[.loans[] | select(.type.id=="audiobook")]' > $TMP_LOANS
  getListLength $TMP_LOANS
  x=0
  while [ $x -le $(($listLength - 1 )) ]
  do
    jq --argjson idx "$x" -r '.[$idx]' $TMP_LOANS > $TMP_INDV_LOAN
    card=$(jq -r '.cardId' $TMP_INDV_LOAN)
    libraryName=$(echo "$syncPayload" | jq --arg foo "$card" -r '(.cards[] | select(.cardId==$foo)) | .library.name')
    libraryName="$libraryName / $card"
    bookInfo=$(jq -r '.title + "_" + .firstCreatorName + "_" + .id + "_" + .publisherAccount.name + "_" + (.formats[0].duration // "Not Provided")' $TMP_INDV_LOAN)
    expirationDate=$(jq -r '.expireDate' $TMP_INDV_LOAN)
    formatDate $expirationDate
    x=$(( $x + 1 ))
    allResults="${allResults}""${bookInfo}"_"${libraryName}"_"${formattedDate}""${formatCharacters}"
  done
  echo "$allResults" | column -s _ -t
  rm -rf $TMP_DIR
}

searchForBook() {
  getSyncPayload
  local advantageKeys
  local searchUri
  local libraryParam
  local TMP_PAYLOAD=$TMP_DIR/searchPayload.txt
  local TMP_INDV_BOOK=$TMP_DIR/individualBook.txt
  allResults="Title_Author_BookId_Publisher_Duration_Available Now_Holdable${formatCharacters}" # these are the headers for the results
  searchString="${searchString// /%20}" # url encodes any spaces
  libraryParam="&libraryKey="
  advantageKeys=$(echo "$syncPayload" | jq -r '[.cards[].advantageKey] | join(",")')
  iter=0
  # construct query string with library keys  '?libraryKey=KEY_1&libraryKey=KEY_2&query=QUERY_INPUT'
  for i in ${advantageKeys//,/ }
  do
    if [ $iter == 0 ]; then
      searchUri="?libraryKey=$i"
    else
      searchUri="$searchUri""$libraryParam"$i
    fi
    ((iter=iter+1))
  done
  searchUri="$THUNDER_ENDPOINT"/media/search/"$searchUri"\&query="$searchString"
  # hit search endpoint with library abbreviations and query string (https://thunder.api.overdrive.com/v2/media/search)
  mkdir -p $TMP_DIR
  curl -H "Accept: application/json" -X GET -f -s "$searchUri" | jq -r '[.[] | select(.type.id=="audiobook")]' > $TMP_PAYLOAD
  # A strange issue was encountered here: running the script through sh is jacking up the json output from the search endpoint. It is breaking the data up into multiple lines.
  # if you run it through ide, it seems to work fine. Not sure what the difference is
  # an example of a problematic jq call is here "searchPayload=$(echo "$searchPayload" | jq -r '[.[] | select(.type.id=="audiobook")]')"
  # LEARNING - For whatever reason, the json isn't split up at all if sh runs jq and it reads the json from a file. So for the complicated payloads like the book searches, I'll just store it in a file and read it from there.
  getListLength $TMP_PAYLOAD
  # loop through each result to get specific details
  x=0
  while [ $x -le $(($listLength - 1 )) ]
  do
    jq --argjson idx "$x" -r '.[$idx]' $TMP_PAYLOAD > $TMP_INDV_BOOK
    # can't reuse this bookInfo for other similar things (like for loans or holds) because some of fields and properties are slightly different
    bookInfo=$(jq -r '.title + "_" + .firstCreatorName + "_" + .id + "_" + .publisher.name + "_" + (.formats[0].duration // "Not Provided")' $TMP_INDV_BOOK) # grabbing an arbitrary duration. The formats are all similar, with only minutes different duration between them.
    # get the patron's libraries that have this book as a comma separated list
    availableLibraries=$(jq -r '.siteAvailabilities | keys | join(",")' $TMP_INDV_BOOK)
    # now to get the availability of the various libraries, loop through the csv created earlier
    local availableLocations=""
    local holdableLocations=""
    local isAvailable
    local isHoldable
    local id
    # TODO is this needlessly expensive? Would be lovely not to have to do a subloop. I can't figure out a select statement in the jq to give me what I want though
    for i in ${availableLibraries//,/ }
    do
      # get the unique library id for this library
      id=$(echo "$syncPayload" | jq --arg foo "$i" -r '(.cards[] | select(.advantageKey==$foo)) | .cardId')
      # check if library has it available
      isAvailable=$(jq -e -r '.siteAvailabilities.'\"$i\"'.isAvailable|tostring' $TMP_INDV_BOOK) # need to escape the double quote for the case where the library location has a hyphen
      isHoldable=$(jq -e -r '.siteAvailabilities.'\"$i\"'.isHoldable|tostring' $TMP_INDV_BOOK)
      # if it does, assign it to the isAvailable var
      if [[ $isAvailable == true ]]; then
        availableLocations=${availableLocations}"$i:$id "
      # if not, check if it is holdable, if so assign it to the isHoldable var
      elif [[ $isHoldable == true ]]; then
        holdableLocations=${holdableLocations}"$i:$id "
      fi
    done
    x=$(( $x + 1 ))
      if [[ $availableLocations == "" ]]; then
        availableLocations="<<unavailable>>"
      fi
      if [[ $holdableLocations == "" ]]; then
        holdableLocations="<<check it out instead!>>"
      fi
    allResults="${allResults}""${bookInfo}"_"${availableLocations}"_"${holdableLocations}""${formatCharacters}"
  done
  rm -rf $TMP_DIR
  echo "$allResults" | column -s _ -t
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
search=0
loans=0

########################################
#######           MAIN           #######
########################################
function mainScript() {
  rm -rf $TMP_DIR
  # TODO: add if statement for the checkout path
  getSyncPayload
  if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Please install jq by following the instructions here https://stedolan.github.io/jq/download/"
    exit
  fi

  if [ $search == 1 ]; then
    local queryLength=${#searchString}
    if [ -z "$searchString" ] || [ "$queryLength" -lt 2 ]; then
      echo "ERROR: You must supply search string that is two or more characters"
      exit
    else
      echo "Searching your libraries for audiobooks returned by the query \"$searchString\""
      searchForBook
    fi
  fi

  #viewing loans
  if [ $loans == 1 ]; then
   printLoans
   exit
  fi

  # downloading a book
  if [ $downloadBook == 1 ]; then
    local cardId
    local bookId
    setUpDownloadPath
    echo "Enter Library Card: "; read -r cardId; checkIfValidCardId "$cardId"; echo "Enter Book Id: "; read -r bookId; echo
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
    echo "Enter Library Card: "; read -r cardId; checkIfValidCardId "$cardId"; echo "Enter Book Id: "; read -r bookId; echo
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
    if [ -z "$authCode" ]; then
      echo "ERROR: You must supply an authentication code retrieved from the Libby app. Example: shibby -a 12345678"
    else
      echo "authorizing with code $authCode"
      syncWithLibby "$authCode"
      getSecondToken
      exit
    fi
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
  -r, --resync                  Start here! Force a new token retrieval (sometimes needed as previously provided tokens can expire)
  -a, --auth [AUTH CODE]        Login with numeric code generated from Libby app
  -s, --search [SEARCH STRING]  Searches all your libraries for books that match the search string
  -c, --checkout                Checkout a book. You will be prompted for the library card id (use the --list command to see these) and the book id (get this from the overdrive website URL)
  -d [PATH]                     Downloads the audiobook to the location provided as an argument. You will be prompted for the library card and the book id to download.
  --list                        Shows all your libraries and the respective card Ids
  --loans                       Shows all the current loans you have at your libraries
  --debug                       Runs script in BASH debug mode (set -x)
  -h, --help                    Display this help and exit
  --version                     Output version information and exit
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
    -s|--search) shift; searchString=${1}; search=1 ;;
    -a|--auth) shift; authCode=${1}; auth=1 ;;
    -c|--checkout) checkoutBook=1 ;;
    -d) shift; DOWNLOAD_PATH=${1}; downloadBook=1 ;;
    --loans) loans=1 ;;
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