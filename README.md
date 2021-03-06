# CLDictP
A command line dictionary written in Perl using Merriam-Webster APIs.

- Merriam-Webster Learner

- Merriam-Webster Collegiate

For each entry, it contains:

- Pronunciation: IPA(International Phonetic Alphabet)

- Part of Speech

- Grammar

- Definition

- Common Usage

- Examples

All searched words are saved in the set and saved to `searched.txt`.

It also save searched words and definitions into the file `quizlet.txt` so that they can be imported into [Quizlet](https://quizlet.com/) which makes flashcards. The format is:

- between term and definition: `$`

- between cards: `---`

## Usage

1. Get API Keys: [DictionaryAPI](https://www.dictionaryapi.com/).

2. Add API Keys to `api_template.json` and change the file name to `api.json`.

3. Install dependencies with

``` bash
$ cpan Term::ANSIColor Term::ReadKey LWP::UserAgent LWP::Protocol::https Readonly XML::LibXML JSON::XS Data::Dumper Set::Light
```

4. Run the script with

``` bash
$ perl dict.pl
```

5. To exit, use Ctrl+D.


## Demo

![demo_gif](./demo.gif)

## License

This project is under [GNU General Public License v3.0](./LICENSE)
