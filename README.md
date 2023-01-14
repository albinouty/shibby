
# shibby

shibby is a shell script for Libby (get it? sh-ibby...you get it). With the move to Libby, the mp3 files for audiobooks are no longer easily accessible like they once were directly through Overdrive. This tool gives you access to those files again...

## Installation
Because shibby is a bash script, it doesn't requier much in terms of installation. Just download it and run it (assuming you have `jq`, read more below).

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

## Usage/Examples
To see everything shibby can do, simply pass in `-h` or `--help`
```shibby -h```

Very first thing should be a `resync`. This is an important step and one that should be done again if you run into snags after using shibby for a while.

```sh ./shibby.sh -r```

Once you have done that, it's time to authenticate shibby. Following the instructions in the Installation section, get the Libby authentication code and run this command: 

```sh ./shibby.sh -a 12345678```

Now shibby is authenticated. You will need to get the unique card IDs Libby assigns to your various library cards. These don't change, but you may to list them out occasionally as you checkout and download various books. 

```sh ./shibby.sh --list```

You will be given an output that looks like this: 

```
Library          CardId
------           ------
Library 1        123456
Library 2        654321
```

Next, because shibby is in its infancy, I don't have a way yet to use shibby to search for a book. **You will use your library's Overdrive website to search for the books you want**. Once you find it, click on the book and in the URL. The book ID you need to grab will be directly after `media/` in the URL. 

For example, 
- if the url is `www.libraryname.overdrive.com/media/4549230?c=2838`
  - the book ID in this case is `4549230`
- if the url is `ww.libraryname.overdrive.com/media/27324`
  - the book ID in this case is `27324`
 You will need the book ID to checkout or download. 

 You can checkout a book through shibby. To do this, run this command
 
 ```sh ./shibby.sh -c```
 
 You will then be prompted for the `Card ID` (you get this from the `--list` command) and the `Book Id` (you get this from the overdrive website).

 Downloading a book is similar to checking one out. The book must first be checked out to you, then run this command: 

 ```sh ./shibby.sh -d file/path/where/you/want/it/to/download```

 NOTE - the filepath in the command is totally optional. It will download to `~/audiobooks` if you don't pass anything in. 

 After running the command, you'll be prompted for the `Card Id` and the `Book Id`, just like when checking out a book. 

 shibby will then download the book to the location you have chosen. shibby will add /AUTHOR/BOOK_TITLE to the path and within the directory with the title's name will be the various mp3 files for the audiobook.



## FAQ

#### Is this legal?

Yep! This script doesn't strip any proprietary DRM from files or do any sort of encryption cracking. The locations it accesses for the files are all publicly accessible and are authenticated through the Libby app and a valid library card.

#### Can I get ebooks from this?

No. The script was built with audiobooks in mind. Using this tool for ebooks is in the cards for a future enhancement, though. That being said, today you definitely can checkout any book, regardless of format.

#### What features are you planning on adding in the future?

- Search for a book
- Get more info about a specific book
- View loans
- View/place holds
- Return books
- General refinements as things are admittedly unpolished right now
- Maybe ebook support



## Acknowledgements

 - chbrown for the original Overdrive script which inspired me to make this one for Libby. [Check it out here.](https://github.com/chbrown/overdrive)
 - lillius for his version of a Libby app which I attempted to reverse engineer so I could make shibby in bash. [Check it out here.](https://github.com/lullius/pylibby)



## Version

![MIT License](https://img.shields.io/badge/shibby-alpha-green)

