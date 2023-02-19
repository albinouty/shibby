# shibby

shibby is a shell script for Libby (get it? sh-ibby...you get it). With the move to Libby, the mp3 files for audiobooks are no longer easily accessible like they once were directly through Overdrive. This tool gives you access to those files again...

## Installation
Because shibby is a bash script, it doesn't require much in terms of installation. Just download it and run it (assuming you have `jq`, read more below).

A few things will be needed for shibby to work properly. 

#### jq
I tried to write this in a way where it requires minimal dependencies. That being said, you will need `jq` installed for this script to work. You can install it [here](https://stedolan.github.io/jq/).

#### A valid library card
Talk to your library about getting a card. Many offer the ability to have an electric card only. As long as you can log in to the library's Overdrive site, you will be fine.

#### The Libby app
Whatever your opinion of Libby is, the fact of the matter is that the powers that be are going all in on Libby. In order for shibby to work, you will also need to have the Libby app, and your card(s) added to it. 
[Get it here.](https://www.overdrive.com/apps/libby#GetTheApp)

#### Libby authentication code
After you have logged in to the Libby app and added your card(s), you will need to authenticate shibby to access your account to checkout and download books. 

Within the Libby app find the `Settings` location. Within that area, there will be an option called `Copy To Another Device`. This code will need to be passed in to shibby to properly authenticate the script. See the Usage section for how to do that. 

#### Overdrive website
Libraries all have their own Overdrive website where you can checkout ebooks and audiobooks with your library card. Check with your library to get the link to their overdrive site. 

#### A way to run a shell script 
I developed this script on a Mac, but I don't see any reason why it wouldn't run on Linux (I haven't tried it, though). I wouldn't even be surprised if this could run on Windows, provided you have the proper tools in place there to run bash scripts.

## Setup
Very first thing you do should be a `resync` or shibby won't work. This is an important step and one that should be done again if you run into snags after using shibby for a while.

```shibby -r```

Once you have done that, it's time to authenticate shibby. Following the instructions in the Installation section, get the Libby authentication code and run this command:

```shibby -a 12345678```

## Usage/Examples
To see everything shibby can do, simply pass in `-h` or `--help`

```shibby -h```

```
Options:
  -r
        Start here! Force a new token retrieval (sometimes you may need to do this again as previously provided tokens can expire)

  -a [AUTH CODE]
        Login with numeric code generated from Libby app

  -s [SEARCH STRING]
        Searches all your libraries for books that match the search string

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
        Allows you to pass in the book id (which is shown in commands like search, holds, or loans). This is required for checking out a book, placing holds, and downloading.

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
```

### Viewing your libraries
Many of the things shibby can do will require a library ID. shibby can show you the IDs that Libby assigns to your libraries. These don't change, but you may to list them out occasionally as you checkout and download various books. Also shown is the unique key assigned to the library by libby. This also doesn't change and will come in handy when determining which libraries have books you want when searching.

```shibby --list```

You will be given an output that looks like this: 

```
Library                          CardId       Libby Key    
---------                        ---------    ---------
Boston Public Library            123456       bpl                      
San Fransico Public Library      654321       sfpl                     
Fulton County Library System     98765        fulcolibrary             
Salt Lake City Public Library    123456789    slcpl                    
```

### Searching
**Option 1: Let shibby search for you!**

You can search for books you want with shibby in your terminal prompt. Currently, shibby will only return audiobook results. To do this, simply run a command like the one below:

`shibby -s "moby dick"`

Once you do that, you will be given some results that look like this: 
```
Searching your libraries for audiobooks returned by the query "moby dick"
9 books returned...
Title       Author            BookId   Publisher            Duration  Available Now  Holdable
Moby Dick   Herman Melville   317297   Tantor Media, Inc.   25:29:38  library1:1234                                    
Moby Dick   Herman Melville   150900   Books on Tape        24:34:14  library1:1234  library2:5678
...
...
...
```

Scan through the results, and when you see a book you want, check which library it is at. The values in the `Available Now` and `Holdable` columns are your libraries. An example is `library1:1234`. The first part is an abbreviation of your library, the second part is the library ID that you will provide to the checkout (`-c`) and download (`-d`) commands.

The `Available Now` column is libraries where the book is available for immediate checkout. The `Holdable` column means that library carries the book, but you have to place a hold for it as it is not currently available to checkout.

You also will see the `BookId`. You can use this value to view the book directly in your browser if you want. Read on to the next section to learn about that.

Finally, to complete the example, given the information above book `317297` is available immediately at library1 (id `1234`) and nowhere else. Book `150900` is available immediately at library1 (id `1234`) and a hold can be placed for it at library2 (id `5678`)

**Option 2: Use your browser!**

You can use your library's Overdrive website to search for the books you want. Once you find it, click on the book. Then look at the URL and the book ID you need to grab will be directly after `media/`. 

For example, 
- if the url is `www.libraryname.overdrive.com/media/4549230?c=2838`
  - the book ID in this case is `4549230`
- if the url is `ww.libraryname.overdrive.com/media/27324`
  - the book ID in this case is `27324`
 You will need the book ID to checkout or download. 

### Checking out a book
 You can checkout a book through shibby. To do this, run this command
 
 ```shibby -c -L 123456 -b 654321```
 
You must pass in `-L` which is the library id where you want to check out the book from. You must also pass `-b` which is the book id.

### Placing a hold
You can place a hold for a book through shibby. To do this, run this command

```shibby -H -L 123456 -b 654321```

You must pass in `-L` which is the library id where you want to place the hold. You must also pass `-b` which is the book id.

### Returning a book

```shibby -R -L 123456 -b 654321```

To return a book, you use the `-R` option, along with specifying the library (`-L`) and the book (`-b`).

### Viewing your loans and holds
 Shibby will show you which books you have checked out currently and also which books you have holds for.

 `shibby --loans`

 ```
Found 4 books...
Title                               Author            BookId   Publisher               Duration  Library / Id                                         Due Date
The Mountain Between Us             Charles Martin    206800   Books on Tape           09:56:51  Boston Public Library / 123456                       Tuesday, 14 February 2023
The Adventures of Huckleberry Finn  Mark Twain        61470    Blackstone Audio, Inc.  09:22:36  Fort Vancouver Regional Library District / 44553334  Monday, 27 February 2023
Nasty, Brutish, and Short           Scott Hershovitz  6491010  Books on Tape           09:31:20  Fort Vancouver Regional Library District / 44553334  Sunday, 26 February 2023
Finlay Donovan Jumps the Gun        Elle Cosimano     8916746  Macmillan Audio         08:38:50  San Fransico Public Library / 9876543                Tuesday, 21 February 2023
 ```

`shibby --holds`

 ```
Found 2 books...
Title                                  Author          BookId   Duration      Hold Position  Estimated Wait (Days)  Library / Id                           Hold Placed On
Finlay Donovan Is Killing It--A Novel  Elle Cosimano   5462436  09:59:50      310 of 438     638                    Beehive Library Consortium / 1234  Monday, 23 January 2023
Mrs. Harris Goes to Paris / Mrs. Har   Paul Gallico    9216126  10:16:14      30 of 81       140                    Beehive Library Consortium / 1234  Sunday,  4 December 2022 
```

### Downloading a book
 Downloading a book is similar to checking one out. The book must first be checked out to you, then run this command: 

 ```shibby -d -L 12345 -b 654321```

This will download to `~/audiobooks`. If you'd like to specify where to download the files, use this command: 

```shibby --download=file/path/where/you/want/it/to/download -L 12345 -b 654321```

The `-L` represents the library you want to download from. The `-b` represents the id of the book you want to download.

 shibby will then download the book and will add `/AUTHOR/BOOK_TITLE` to the download path and within the directory will be a subfolder named after the book which will contain the various mp3 files for the audiobook.

## FAQ

#### Is this legal?

Yep! This script doesn't strip any proprietary DRM from files or do any sort of encryption cracking. The locations it accesses for the files are all publicly accessible and are authenticated through the Libby app and a valid library card.

#### Can I get ebooks from this?

No. The script was built with audiobooks in mind. Using this tool for ebooks is in the cards for a future enhancement, though.

#### What features are you planning on adding in the future?

- Get more info about a specific book
- General refinements as things are admittedly unpolished right now
- ebook support

## Acknowledgements

 - chbrown for the original Overdrive script which inspired me to make this one for Libby. [Check it out here.](https://github.com/chbrown/overdrive)
 - Nathaniel Landau for his cli boilerplate template which I used. [Check it out here.](https://natelandau.com/boilerplate-shell-script-template/)

## Version

![MIT License](https://img.shields.io/badge/shibby-alpha-green)