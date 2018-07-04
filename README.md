# CLDictP
A command line dictionary written in Perl using Merriam-Webster APIs.

## Usage

1. Get API Keys: [DictionaryAPI](https://www.dictionaryapi.com/).

1. Add API Keys to `api_tempalte.json` and change the file name to `api.json`.

1. Install dependencies with 

``` bash
cpan Term::ANSIColor Term::ReadKey LWP::UserAgent LWP::Protocol::https Readonly XML::LibXML JSON::XS Data::Dumper Set::Light
```

1. Run the script with

1. To exit, use Ctrl+D

``` bash
perl dict.pl
```

## Demo

!(demo_gif)[https://media.giphy.com/media/14ug46DiMGxyDpA7z5/giphy.gif]
