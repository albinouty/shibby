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
OVERDRIVE_DATE_FORMAT="%Y-%m-%dT%H:%M:%SZ" # unfortunately not all dates in their APIs conform to this
SHIBBY_DATE_FORMAT="+%A, %_d %B %Y" # could add at %r %Z to the end of this to get the time of day. I think it takes up too much console space though
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
_LIBRARY="" # used to hold the context library passed in for certain commands
_BOOK="" # used to hold the context book id passed in for certain commands
libraryAndBookRequiredError="ERROR: You must pass in both a library (-L) and a book id (-b) with this command"

########################################
#######           UTIL           #######
########################################
# These shared utilities provide many functions which are needed to provide
# the functionality in this script
# utilsLocation="${scriptPath}/lib/utils.sh" # Update this path to find the utilities.

getToken() {
  local chipPayload
  # Requests a brand new token, extracts the value, and stores it in the identity file
  chipPayload=$(curl -X POST -f -s $SVC_ENDPOINT"/chip" && echo "" || echo "Could not retrieve token.")
  getIdentityPayload "$chipPayload"
}

# TODO: combine common curl arguments into a variable
# TODO: combine common jq arguments into a variable

getSecondToken() {
  local chipPayload
  local tokenValue
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
  local cloned
  code=$1
  tokenValue=$(cat "$TOKEN_PATH")
  JSON_TMP='{"code": "%s"}\n'
  JSON=$(printf "$JSON_TMP" "$code")
  clonePayload=$(curl -H "Accept: application/json" -H "Content-Type: application/json" -H "Authorization: Bearer $tokenValue" -d "$JSON" -X POST -f -s $SVC_ENDPOINT"/chip/clone/code")
  cloned=$(echo "$clonePayload" | jq -r '.result')
  if [ $cloned == "cloned" ]; then
    echo "You are successfully authorized and synced with your Libby app."
  else
   echo "Something went wrong. Server responded with"
   echo "$clonePayload"
  fi
}

printLibraries() {
  echo "$syncPayload" | jq -r '"Library:CardId:Libby Key", "---------:---------:---------", (.cards[] | .library.name + ":" + .cardId + ":" + .advantageKey)' | column -s: -t
  # TODO: find a better way to generate a table with headers
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
    echo "Missing token, be sure to resync and authenticate with a Libby code"
    exit
  fi
}

formatDate() {
  theDate=$1
  theFormat=$2
  # format the date for both macs and linux date functions. It'll pick whatever one can run.
  formattedDate=$(date -jf "$theFormat" "$theDate" "$SHIBBY_DATE_FORMAT" 2> /dev/null || date -d "$theDate" "$SHIBBY_DATE_FORMAT" 2> /dev/null)
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
  echo "Checking out $bookName from $libraryName..."
  loanPayload=$(curl -H "Accept: application/json" -H "Authorization: Bearer $tokenValue" -X POST -f -s $SVC_ENDPOINT"/card/$cardId/loan/$bookId")
  expireDate=$(echo "$loanPayload" | jq -r '.expireDate')
  if [ -n "$expireDate" ]; then
    local titleAndAuthor
    titleAndAuthor=$(echo "$loanPayload" | jq -r '.title + " by " + .firstCreatorName')
    formatDate $expireDate $OVERDRIVE_DATE_FORMAT
    echo "Successfully checked out $titleAndAuthor from $libraryName. It is due back on $formattedDate"
  else
    echo "Something went wrong during checkout. Server responded with the following..."
    echo "$loanPayload"
  fi
}

placeHold() {
  local cardId
  local bookId
  cardId=$1
  bookId=$2
  getBookInfo "$bookId"
  bookName=$(echo "$bookInfo" | jq -r '.title')
  tokenValue=$(cat "$TOKEN_PATH")
  libraryName=$(echo "$syncPayload" | jq --arg foo "$cardId" -r '(.cards[] | select(.cardId==$foo)) | .library.name')
  echo "Placing a hold for $bookName at $libraryName..."
  holdPayload=$(curl -H "Accept: application/json" -H "Authorization: Bearer $tokenValue" -X POST -f -s $SVC_ENDPOINT"/card/$cardId/hold/$bookId")
  holdPosition=$(echo "$holdPayload" | jq -r '.holdListPosition')
  if [ -n "$holdPosition" ]; then
    local titleAndAuthor
    local copies
    local estWait
    copies=$(echo "$holdPayload" | jq -r '.ownedCopies')
    estWait=$(echo "$holdPayload" | jq -r '.estimatedWaitDays')
    titleAndAuthor=$(echo "$holdPayload" | jq -r '.title + " by " + .firstCreatorName')
    formatDate $expireDate $OVERDRIVE_DATE_FORMAT
    echo -e "Successfully placed a hold for $titleAndAuthor at $libraryName. \n\r \
    Your hold position is $holdPosition. The library owns $copies copies and your estimated wait is $estWait days."
  else
    echo "Something went wrong when trying to place the hold. Server responded with the following..."
    echo "$holdPayload"
  fi
}

returnTheBook() {
  local cardId
  local bookId
  cardId=$1
  bookId=$2
  getBookInfo "$bookId"
  bookName=$(echo "$bookInfo" | jq -r '.title')
  tokenValue=$(cat "$TOKEN_PATH")
  libraryName=$(echo "$syncPayload" | jq --arg foo "$cardId" -r '(.cards[] | select(.cardId==$foo)) | .library.name')
  echo "Returning $bookName to $libraryName..."
  returnPayload=$(curl -H "Accept: application/json" -H "Authorization: Bearer $tokenValue" -X DELETE -f -s $SVC_ENDPOINT"/card/$cardId/loan/$bookId")
  # check if the return status is 200
  if [ "$(curl -w '%{http_code}' -H "Accept: application/json" -H "Authorization: Bearer $tokenValue" -X DELETE -f -s $SVC_ENDPOINT"/card/$cardId/loan/$bookId" -o /dev/null)" = "200" ]; then
    echo "The book has been returned. Exiting..."
  else
    echo "ERROR: Something went wrong when returning the book."
  fi
}

setUpDownloadPath() {
  # if the download path option isn't provided, set a default location
  if [ -z "$DOWNLOAD_PATH" ]; then
    echo "No download path provided, will save the audiobook to ~/audiobooks"
    DOWNLOAD_PATH="$HOME/audiobooks"
  else
    echo "Downloading the book to the directory $DOWNLOAD_PATH"
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
    echo "ERROR: The book \"$bookName\" is not checked out at $libraryName ($cardId). Your current loans are:"
    printLoans
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

  bookNameWithSpaces=$(echo "$bookName")
  authorNameWithSpaces=$(echo "$authorName")

  presentDirectory=$(pwd)
  cd "$DOWNLOAD_PATH"
  mkdir -p ./"$authorNameWithSpaces"/"$bookNameWithSpaces"
  cd "$authorNameWithSpaces"/"$bookNameWithSpaces"
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
  curl -o "$bookNameWithSpaces - Part $iter.mp3" -L -f -s -H "Accept: */*" -H "Authorization: Bearer $tokenValue" -H "Cookie: _sscl_d=$SSCL_COOKIE; d=$D_COOKIE" -X GET "$webUrl"/"$line"
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
    if [[ $listLength == 0 ]]; then
        exit
    fi
}

printLoans() {
  local TMP_LOANS=$TMP_DIR/loans.txt
  local TMP_INDV_LOAN=$TMP_DIR/individualLoan.txt
  allResults="Title_Author_BookId_Duration_Library / Id_Due Date${formatCharacters}" # these are the headers for the loans
  mkdir -p $TMP_DIR
  getSyncPayload
  echo "$syncPayload" | jq -r '[.loans[] | select(.type.id=="audiobook" and .isOwned==true)]' > $TMP_LOANS
  getListLength $TMP_LOANS
  x=0
  while [ $x -le $(($listLength - 1 )) ]
  do
    jq --argjson idx "$x" -r '.[$idx]' $TMP_LOANS > $TMP_INDV_LOAN
    card=$(jq -r '.cardId' $TMP_INDV_LOAN)
    libraryName=$(echo "$syncPayload" | jq --arg foo "$card" -r '(.cards[] | select(.cardId==$foo)) | .library.name')
    libraryName="$libraryName / $card"
    bookInfo=$(jq -r '.title + "_" + .firstCreatorName + "_" + .id + "_" + (.formats[0].duration // "Not Provided")' $TMP_INDV_LOAN)
    expirationDate=$(jq -r '.expireDate' $TMP_INDV_LOAN)
    formatDate $expirationDate $OVERDRIVE_DATE_FORMAT
    x=$(( $x + 1 ))
    allResults="${allResults}""${bookInfo}"_"${libraryName}"_"${formattedDate}""${formatCharacters}"
  done
  printResults
  rm -rf $TMP_DIR
}

printHolds() {
  local TMP_HOLDS=$TMP_DIR/holds.txt
  local TMP_INDV_HOLD=$TMP_DIR/individualhold.txt
  allResults="Title_Author_BookId_Duration_Hold Position_Estimated Wait (Days)_Library / Id_Hold Placed On${formatCharacters}" # these are the headers for the holds
  mkdir -p $TMP_DIR
  getSyncPayload
  echo "$syncPayload" | jq -r '[.holds[] | select(.type.id=="audiobook" and .isOwned==true)]' > $TMP_HOLDS
  getListLength $TMP_HOLDS
  x=0
  while [ $x -le $(($listLength - 1 )) ]
  do
    jq --argjson idx "$x" -r '.[$idx]' $TMP_HOLDS > $TMP_INDV_HOLD
    card=$(jq -r '.cardId' $TMP_INDV_HOLD)
    libraryName=$(echo "$syncPayload" | jq --arg foo "$card" -r '(.cards[] | select(.cardId==$foo)) | .library.name')
    libraryName="$libraryName / $card"
    bookInfo=$(jq -r '.title + "_" + .firstCreatorName + "_" + .id + "_" + (.formats[0].duration // "Not Provided") + "_" + (.holdListPosition | tostring) + " of " + (.holdsCount | tostring) + "_" + (.estimatedWaitDays // "Not Provided" | tostring)' $TMP_INDV_HOLD)
    placedDate=$(jq -r '.placedDate' $TMP_INDV_HOLD)
    formatDate $placedDate "%Y-%m-%dT%H:%M:%S" # this date comes through with milliseconds, thus we aren't putting the Z at the end and the command should ignore the extra characters
    x=$(( $x + 1 ))
    allResults="${allResults}""${bookInfo}"_"${libraryName}"_"${formattedDate}""${formatCharacters}"
  done
  printResults
  rm -rf $TMP_DIR
}

AVAILABLE_LOCATIONS=""
HOLDABLE_LOCATIONS=""
# the parameter coming in needs to be the location to a file containing the json for an individual book
getBookAvailability() {
  AVAILABLE_LOCATIONS=""
  HOLDABLE_LOCATIONS=""
  local TMP_INDV_BOOK=$1
  local printWaitTime=$2 # when this is true, the hold section will print the wait time in parenthesis
    # get the patron's libraries that have this book as a comma separated list
    availableLibraries=$(jq -r '.siteAvailabilities | keys | join(",")' $TMP_INDV_BOOK)
    # now to get the availability of the various libraries, loop through the csv created earlier
    local isAvailable
    local isHoldable
    local id
    for i in ${availableLibraries//,/ }
    do
      # get the unique library id for this library
      id=$(echo "$syncPayload" | jq --arg foo "$i" -r '(.cards[] | select(.advantageKey==$foo)) | .cardId')
      # check if library has it available
      isAvailable=$(jq -e -r '.siteAvailabilities.'\"$i\"'.isAvailable|tostring' $TMP_INDV_BOOK) # need to escape the double quote for the case where the library location has a hyphen
      isHoldable=$(jq -e -r '.siteAvailabilities.'\"$i\"'.isHoldable|tostring' $TMP_INDV_BOOK)
      # if it does, assign it to the isAvailable var
      if [[ $isAvailable == true ]]; then
        AVAILABLE_LOCATIONS=${AVAILABLE_LOCATIONS}"$i:$id "
      # if not, check if it is holdable, if so assign it to the isHoldable var
      elif [[ $isHoldable == true ]]; then
        if [[ $printWaitTime == 1 ]]; then
          estimatedWait=$(jq -e -r '.siteAvailabilities.'\"$i\"'.estimatedWaitDays' $TMP_INDV_BOOK)
          HOLDABLE_LOCATIONS=${HOLDABLE_LOCATIONS}"$i:$id ($estimatedWait) | "
          else
          HOLDABLE_LOCATIONS=${HOLDABLE_LOCATIONS}"$i:$id "
        fi
      fi
    done
      if [[ $AVAILABLE_LOCATIONS == "" ]]; then
        AVAILABLE_LOCATIONS="<<unavailable>>"
      fi
      if [[ $HOLDABLE_LOCATIONS == "" ]]; then
        HOLDABLE_LOCATIONS="<<check it out instead!>>"
      elif [[ $printWaitTime == 1 ]]; then
        HOLDABLE_LOCATIONS="${HOLDABLE_LOCATIONS%???}" # remove last three characters so the final hold entry doesn't have a separator after it
      fi
}

constructAndExecuteSearch() {
    getSyncPayload
    local tmpPayload=$1
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
    curl -H "Accept: application/json" -X GET -f -s "$searchUri" | jq -r '[.[] | select(.type.id=="audiobook")]' > $TMP_PAYLOAD
    # A strange issue was encountered here: running the script through sh is jacking up the json output from the search endpoint. It is breaking the data up into multiple lines.
    # if you run it through ide, it seems to work fine. Not sure what the difference is
    # an example of a problematic jq call is here "searchPayload=$(echo "$searchPayload" | jq -r '[.[] | select(.type.id=="audiobook")]')"
    # LEARNING - For whatever reason, the json isn't split up at all if sh runs jq and it reads the json from a file. So for the complicated payloads like the book searches, I'll just store it in a file and read it from there.
}

printResults() {
    echo -e "$allResults" | column -s _ -t
}

searchForBook() {
  local advantageKeys
  local searchUri
  local libraryParam
  local TMP_PAYLOAD=$TMP_DIR/searchPayload.txt
  local TMP_INDV_BOOK=$TMP_DIR/individualBook.txt
  allResults="Title_Author_BookId_Publisher_Duration_Available Now_Holdable${formatCharacters}" # these are the headers for the results
  mkdir -p $TMP_DIR
  constructAndExecuteSearch $TMP_PAYLOAD
  getListLength $TMP_PAYLOAD
  # loop through each result to get specific details
  x=0
  while [ $x -le $(($listLength - 1 )) ]
  do
    jq --argjson idx "$x" -r '.[$idx]' $TMP_PAYLOAD > $TMP_INDV_BOOK
    # can't reuse this bookInfo for other similar things (like for loans or holds) because some of fields and properties are slightly different
    bookInfo=$(jq -r '.title + "_" + .firstCreatorName + "_" + .id + "_" + .publisher.name + "_" + (.formats[0].duration // "Not Provided")' $TMP_INDV_BOOK) # grabbing an arbitrary duration. The formats are all similar, with only minutes different duration between them.
    getBookAvailability $TMP_INDV_BOOK 0
    allResults="${allResults}""${bookInfo}"_"${AVAILABLE_LOCATIONS}"_"${HOLDABLE_LOCATIONS}""${formatCharacters}"
    x=$(( $x + 1 ))
  done
  rm -rf $TMP_DIR
  printResults
}

getMoreInfo() {
  bookId=$1
  local TMP_INDV_BOOK=$TMP_DIR/individualBook.txt
  local TMP_PAYLOAD=$TMP_DIR/searchPayload.txt
  mkdir -p $TMP_DIR
  local bookName
  buffer="..........................................."
  bookInformation=""
  addInformation() {
    heading=$1
    infoToAdd=$2
    bookInformation=$bookInformation$heading"_"$infoToAdd$formatCharacters
  }
  getSyncPayload
  getBookInfo $bookId
  # get book info, strip off whatever you can DONE
  # get the id of the book DONE
  # run search for book title (set the searchquery variable)
  # from the payload, get the book where the id equals what we want
  # run existing logic to get holdable and available locations
  # look for the book id in the sync payload to say which libraries it is checked out and which it is held at
  bookName=$(echo "$bookInfo" | jq -r '.title')
  bookId=$(echo "$bookInfo" | jq -r '.id')
  echo "Getting more information for the requested book..."

  # get specifics about holds and availability
  searchString=$bookName
  constructAndExecuteSearch $TMP_PAYLOAD
  jq --arg book "$bookId" -r '.[] | select(.id==$book)' $TMP_PAYLOAD > $TMP_INDV_BOOK
  getBookAvailability $TMP_INDV_BOOK 1

  bookAuthor=$(echo "$bookInfo" | jq -r '.firstCreatorName')
  publisher=$(echo "$bookInfo" | jq -r '.publisher.name')
  duration=$(echo "$bookInfo" | jq -r '.formats[0]?.duration // "N/A"')
  publicDomain=$(echo "$bookInfo" | jq -r '.isPublicDomain')
  languages=$(echo "$bookInfo" | jq -r '[.languages[]?.name] | join(", ")')
  maturity=$(echo "$bookInfo" | jq -r '.ratings.maturityLevel.name')
  awards=$(echo "$bookInfo" | jq -r '[.awards[]?.description] | join(", ") | if . == "" then "none" else . end')
  subjects=$(echo "$bookInfo" | jq -r '[.subjects[]?.name] | join(", ")')
  lexile=$(echo "$bookInfo" | jq -r '(select(.levels | length > 0) | .levels[]? | select(.id=="lexile") | .value) // "Not provided"')
  readingLevel=$(echo "$bookInfo" | jq -r '(select(.levels | length > 0) | .levels[]? | select(.id=="reading-level") | .value) // "Not provided"')
  format=$(echo "$bookInfo" | jq -r '.type.name')
  publishDate=$(echo "$bookInfo" | jq -r '.publishDate')
  formatDate $publishDate $OVERDRIVE_DATE_FORMAT
  publishDate=$formattedDate" (for this specific format)"
  series=$(echo "$bookInfo" | jq -r '. | if has("detailedSeries") then .detailedSeries.seriesName else "Not part of a series" end')
  bookNumber=$(echo "$bookInfo" | jq -r '. | if has("detailedSeries") then .detailedSeries.readingOrder // "N/A" else "N/A" end')
  narrators=$(echo "$bookInfo" | jq -r '[.creators[]? | select(.role=="Narrator") | .name] | join(", ") | if . == "" then "N/A" else . end')
  bookDesc=$(echo "$bookInfo" | jq -r '.description' | sed -e 's/<[^>]*>//g') # also strips out the html tags

  # This is ugly, I know. Could use columns or something else, but I want the trailing dots to connect the data and this approach is what I found that gave that to me
  # I tried an associated array (map), but it's support across bash versions varies and I didn't want to deal with that
  values=("$bookName" \
  "$bookAuthor" \
  "$bookId" \
  "$format" \
  "$duration" \
  "$narrators" \
  "$publisher" \
  "$languages" \
  "$maturity" \
  "$subjects" \
  "$awards" \
  "$publishDate" \
  "$series" \
  "$bookNumber" \
  "$lexile" \
  "$readingLevel" \
  "$publicDomain" \
  "$HOLDABLE_LOCATIONS"\
  "$AVAILABLE_LOCATIONS" \
  "$bookDesc")

  # must match the order you put the corresponding values into the "values" array
  headers="\
  Title \
  Author \
  BookId \
  Format \
  Duration \
  Narrator \
  Publisher \
  Language \
  Maturity \
  Subjects \
  Awards \
  PublishDate \
  Series \
  BookNumber \
  LexileScore \
  ReadingLevel \
  InPublicDomain \
  AvailableToHoldAt \
  AvailableToCheckoutAt \
  Description
  "
  iter=0
  for x in $headers; do
      printf '%.30s %s\n' "$x""$buffer" "${values[$iter]}";
      ((iter=iter+1));
  done
  rm -rf $TMP_DIR
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
holds=0
placeHold=0
returnBook=0
moreInfo=0

########################################
#######           MAIN           #######
########################################
function mainScript() {
  rm -rf $TMP_DIR
  if ! command -v jq &> /dev/null; then
    echo "jq could not be found. Please install jq by following the instructions here https://stedolan.github.io/jq/download/"
    exit
  fi
  # if the token file is empty, request a new token
  if [ ! -s $TOKEN_PATH ]; then
    echo "WARNING: no token found, requesting one and writing it to the token.id file"
    getToken
    # if the token file is still empty, exit or prompt user to now authenticate
    if [ ! -s $TOKEN_PATH ]; then
      echo "ERROR Unable to request a new token at this time."
      exit
    else
      echo "Successfully retrieved a new token. ***This must now be authenticated with the -a option and a code from Libby before you can continue.***"
      exit
    fi
  fi
  getSyncPayload

  # getting more info about a specific book
  if [ $moreInfo == 1 ]; then
    if [ "$_BOOK" != "" ]; then
      getMoreInfo "$_BOOK"
    else
      echo "ERROR: You must pass a book id (-b) with this command"
      exit
    fi
  fi

 # searching for books
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

  # viewing loans
  if [ $loans == 1 ]; then
   printLoans
   exit
  fi

  # viewing holds
  if [ $holds == 1 ]; then
   printHolds
   exit
  fi

  # downloading a book
  if [ $downloadBook == 1 ]; then
    setUpDownloadPath
    if [ "$_LIBRARY" != "" ] && [ "$_BOOK" != "" ]; then
      checkIfValidCardId "$_LIBRARY"
      download "$_LIBRARY" "$_BOOK"
    else
      echo "$libraryAndBookRequiredError"
      exit
    fi
  fi

  # checking out a book
  if [ $checkoutBook == 1 ]; then
    if [ "$_LIBRARY" != "" ] && [ "$_BOOK" != "" ]; then
      checkIfValidCardId "$_LIBRARY"
      checkout "$_LIBRARY" "$_BOOK"
    else
      echo "$libraryAndBookRequiredError"
      exit
    fi
  fi

  # placing a hold for a book
  if [ $placeHold == 1 ]; then
    if [ "$_LIBRARY" != "" ] && [ "$_BOOK" != "" ]; then
      checkIfValidCardId "$_LIBRARY"
      placeHold "$_LIBRARY" "$_BOOK"
    else
      echo "$libraryAndBookRequiredError"
      exit
    fi
  fi

  # returning a book
  if [ $returnBook == 1 ]; then
    if [ "$_LIBRARY" != "" ] && [ "$_BOOK" != "" ]; then
      checkIfValidCardId "$_LIBRARY"
      returnTheBook "$_LIBRARY" "$_BOOK"
    else
      echo "$libraryAndBookRequiredError"
      exit
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
    if [ "$_LIBRARY" != "" ] || [ "$_BOOK" != "" ]; then
        echo "Resyncing requires only the -r flag to be passed. Did you mean to return a book with -R instead? Exiting..."
        exit
    fi
    echo "resyncing...requesting a new token and writing it to the token.id file"
    getToken
    if [ -s $TOKEN_PATH ]; then
      echo "Successfully retrieved a new token. ***This must now be authenticated with the -a option and a code from Libby before you can continue.***"
    fi
    exit
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
  echo "Options:
  -r
        Start here! Force a new token retrieval. This may be required occasionally as tokens can expire. You must authenticate again after doing this.
  -a [AUTH CODE]
        Authenticate shibby with a numeric code generated from the Libby app
  -s [SEARCH STRING]
        Searches all your libraries for books that match the search string
  -i [-b bookId]
        Retrieves detailed information about the provided book id (-b)
  -c [-L libraryId -b bookId]
        Checkout a book. You must also pass in -L which is the library id (use the --list command to see these) -b which is the book id (get this from the overdrive website URL)
  -R [-L libraryId -b bookId]
        Return a book. You must also pass in -L which is the library id (use the --list command to see these) -b which is the book id (get this from the overdrive website URL)
  -H [-L libraryId -b bookId]
        Place a hold for the book. You must also pass in -L which is the library id (use the --list command to see these) -b which is the book id (get this from the overdrive website URL)
  -d [-L libraryId -b bookId]
        Downloads the audiobook to the default location (~/audiobooks). You must pass in the library id (-L) to download from as well as the book id (-b).
  -L [LIBRARY ID]
        Allows you to pass in the library id (retrieved from the --list command). This is required for checking out a book, placing holds, and downloading.
  -b [BOOK ID]
        Allows you to pass in the book id (which is shown in commands like search, holds, loans, return, or more-info). This is required for checking out a book, placing holds, and downloading.
  --download=/your/custom/path
        Downloads the audiobook to the location provided. You must pass in the library id to download from as well as the book id.
  --list
        Shows all your libraries and the respective card Ids
  --loans
        Shows all the current loans you have at your libraries
  --holds
        Shows all the current holds you have at your libraries
  --debug
        Runs script in BASH debug mode (set -x)
  -h, --help
        Display this help and exit
  --version
        Output version information and exit
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
    -r) resync=1 ;;
    -s) shift; searchString=${1}; search=1 ;;
    -a) shift; authCode=${1}; auth=1 ;;
    -c) checkoutBook=1 ;;
    -i) moreInfo=1 ;;
    -H) placeHold=1 ;;
    -d) downloadBook=1 ;;
    -R) returnBook=1 ;;
    --download) shift; DOWNLOAD_PATH=${1}; downloadBook=1 ;;
    -L) shift; _LIBRARY=${1} ;;
    -b) shift; _BOOK=${1} ;;
    --loans) loans=1 ;;
    --holds) holds=1 ;;
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

#######################################
##       TIME TO RUN THE SCRIPT      ##
#######################################

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