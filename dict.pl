use strict;
use warnings;
use Term::ANSIColor;
use Term::ReadKey;
use LWP::UserAgent;
use LWP::Protocol::https;
use Readonly;
use XML::LibXML;
use JSON::XS;
use Data::Dumper;
use utf8;
use Set::Light;
binmode STDOUT, ":utf8";

##############################
# Constant

# API 
Readonly my $URL_OXFORD_API_ENTRY => "https://od-api.oxforddictionaries.com:443/api/v1/entries/en/";
Readonly my $OXFORD_API_APP_ID => "";
Readonly my $OXFORD_API_APP_KEY => "";
Readonly my $URL_M_W_API_PART_A => "https://www.dictionaryapi.com/api/v1/references/";
Readonly my $URL_M_W_API_PART_B_LEARNER => "learners/xml/";
Readonly my $URL_M_W_API_PART_B_COLLEGIATE => "collegiate/xml/";
Readonly my $URL_M_W_API_PART_C => "?key=";

# Delimiter
Readonly my $DICTIONARY_DELIMITER => "-" x get_screen_width() . "\n";

# Colours
Readonly my $COLOUR_WORD => 'blue';
Readonly my $COLOUR_PRON => 'magenta';
Readonly my $COLOUR_PART_OF_SPEECH => 'blue bold';
Readonly my $COLOUR_GRAM => 'blue';
Readonly my $COLOUR_INFLECTION => 'white bold';
Readonly my $COLOUR_DEFINITION => 'green';
Readonly my $COLOUR_EXAMPLE => 'white';
Readonly my $COLOUR_USAGE => 'yellow';
Readonly my $COLOUR_PHRASE => 'cyan bold';
Readonly my $COLOUR_DELIMITER => 'bright_black';
Readonly my $COLOUR_DICT => 'bright_black';

# Dictionaries
Readonly my $DICT_OXFORD => "Oxford Dictionary";
Readonly my $DICT_M_W_LEARNER =>"Merriam Webster Learner Dictionary";
Readonly my $DICT_M_W_COLLEGIATE => "Merriam Webster Collegiate Dictionary";

# Filenames
Readonly my $SEARCHED_FILENAME => "searched.txt";
Readonly my $LOG_FILENAME => "last.log";
Readonly my $QUIZLET_FILENAME => "quizlet.txt";
##############################
# Global Variables

# user agent
my $ua;

# prompt output
my $output_fh = *STDOUT;

# result ouput to less
my $less_fh;

# log file 
my $log_fh;

# save defs to import to Quizlet
my $quizlet_fh;

# searched word file handler
my $searched_fh;

# words have been searched
my $searched_words = Set::Light->new();

# whether save to quizlet_fh or not
my $save_to_quizlet = 1;

# number of definitions
my $num_defs = 0;

my $M_W_LEARNER_API_KEY;
my $M_W_COLLEGIATE_API_KEY;

##############################


sub print_log {
    my $msg = shift;
    print $log_fh $msg . "\n";
}

sub remove_it_tag {
    my $s = shift;
    $s =~ s/(<it>|<\/it>)//g;
    $s;
}

# print_def($definition_ref, $is_quizlet)
# print definition block
sub print_def {
    my $ref = shift;
    my $is_quizlet = shift;

    foreach my $def_b (@$ref) {

        my $def_example = $def_b->[0];
        my $def = $def_example->[0];

        # print definition
        if ($def ne "") {
            if ($is_quizlet) {
                print $quizlet_fh "*" . $def . "*\n";
            } else {
                print $less_fh colored($def . "\n", $COLOUR_DEFINITION);
            }
        }

        # print example of this definition
        for my $i (1 .. $#{$def_example}) {
            if ($is_quizlet) {
                print $quizlet_fh "\t\t- " . $def_example->[$i] . "\n";
            } else {
                print $less_fh colored("\t\t- " . $def_example->[$i] . "\n", $COLOUR_EXAMPLE);
            }
        }

        # print common usage 
        for my $i (1 .. $#{$def_b}) {
            my $usage = $def_b->[$i]->[0];

            if ($usage ne "") {
                if ($is_quizlet) {
                    print $quizlet_fh "\t" . $usage . "\n";
                } else {
                    print $less_fh colored("\t" . $usage . "\n", $COLOUR_USAGE);
                }
            }

            for my $j (1 .. $#{$def_b->[$i]}) {
                my $example = $def_b->[$i]->[$j];
                if ($is_quizlet) {
                    print $quizlet_fh "\t\t- " . $example . "\n";
                } else {
                    print $less_fh colored("\t\t- " . $example . "\n", $COLOUR_EXAMPLE);
                }
            }
        }
        if ($is_quizlet) {
            print $quizlet_fh "\n";
        } else {
            print $less_fh "\n";
        }
    }
}

#
# format_word_output(\%def)
# Ouput in less
sub format_word_output {
    my $ref_def = shift;

    # word
    print $less_fh colored($ref_def->{word} . "\t", $COLOUR_WORD);

    # pronunciation
    foreach (@{$ref_def->{prons}}) {
        my $formatted = "/" . $_ . "/" . "\t";
        print $less_fh colored($formatted, $COLOUR_PRON);
    }

    # part of speech
    if ($ref_def->{part_of_speech}) {
        print $less_fh colored($ref_def->{part_of_speech} . "\t", $COLOUR_PART_OF_SPEECH);
    }

    # grammar
    if ($ref_def->{gram}) {
        my $formatted = "[" . $ref_def->{gram} . "]";
        print $less_fh colored($formatted, $COLOUR_GRAM);
    }

    print $less_fh "\n";

    # inflections
    if (@{$ref_def->{inflections}}) {
        my $formatted = (join ', ', @{$ref_def->{inflections}});
        print $less_fh colored($formatted . "\n", $COLOUR_INFLECTION);
    }

    # definition
    if (@{$ref_def->{definitions}}) {
        print_def(\@{$ref_def->{definitions}}, 0);
    }

    # phrases
    if (@{$ref_def->{phrases}}) {
        foreach my $phrase_block (@{$ref_def->{phrases}}) {
            my $phrase = $phrase_block->[0];

            print $less_fh colored($phrase, $COLOUR_PHRASE);
            print $less_fh "\n";

            my @d = @$phrase_block[1 .. $#{$phrase_block}];

            print_def(\@d, 0);
        }
    }

    print $less_fh "\n";
}

# format_word_quizlet(/%word_definition)
# Output in quizlet  
sub format_word_quizlet {
    my $ref_def = shift;

    $num_defs += 1;

    # word
    print $quizlet_fh "*" . $num_defs . "* " . $ref_def->{word} . "\t";

    # pronunciation
    foreach (@{$ref_def->{prons}}) {
        my $formatted = "/" . $_ . "/" . "\t";
        print $quizlet_fh $formatted;
    }

    # part of speech
    if ($ref_def->{part_of_speech}) {
        print $quizlet_fh $ref_def->{part_of_speech} . "\t";
    }

    # grammar
    if ($ref_def->{gram}) {
        my $formatted = "[" . $ref_def->{gram} . "]";
        print $quizlet_fh $formatted;
    }

    print $quizlet_fh "\n";

    # inflections
    if (@{$ref_def->{inflections}}) {
        my $formatted = (join ', ', @{$ref_def->{inflections}});
        print $quizlet_fh $formatted . "\n";
    }

    # definition
    if (@{$ref_def->{definitions}}) {
        print_def(\@{$ref_def->{definitions}}, 1);
    }

    # phrases
    if (@{$ref_def->{phrases}}) {
        foreach my $phrase_block (@{$ref_def->{phrases}}) {
            my $phrase = $phrase_block->[0];

            print $less_fh colored($phrase, $COLOUR_PHRASE);
            print $less_fh "\n";

            my @d = @$phrase_block[1 .. $#{$phrase_block}];

            print_def(\@d, 1);
        }
    }
}

#
# get_screen_width()
#
sub get_screen_width {
    my @a = GetTerminalSize();
    if (@a) {
        $a[0];
    } else {
        print $output_fh colored("Failed to get the screen width\n", 'red');
    }
}

#
# blue_search();
# Search prompt in command line
sub blue_search {
    print $output_fh colored("Search: ", 'blue');
}

# find_def($definition)
# find definition, usage, examples
sub find_def {
    my $def_block = shift;

    my @result = ();
    my @defs = ();

    # definition
    my $d = $def_block;
    if ($d =~ /<dt>(.*?)(<vi>|<un>|<\/dt>)/) {
        $d = remove_it_tag($1);
        push @defs, $d;
        print_log("Definition: $1");
    }

    # example
    foreach my $example ($def_block->findnodes('./vi')) {
        my $tmp = remove_it_tag($example->textContent);
        push @defs, $tmp;
        print_log("\tExample: ". $tmp);
    }

    if (@defs) {
        push @result, \@defs;
    }

    # usage and example
    foreach my $un ($def_block->findnodes('./un')) {
        print_log("\tUsage: " . $un);

        my @usages = ();

        $d = $un;
        if ($d =~/<un>(.*?)(<vi>|<\/<un>)/) {
            $d = remove_it_tag($1);
            push @usages, $d;
            print_log("\t\tUsage_def: " . $d);
        }

        foreach my $example ($un->findnodes('./vi')) {
            my $tmp = remove_it_tag($example->textContent);
            push @usages, $tmp;
            print_log("\t\tExample: ". $tmp);
        }

        if (@usages) {
            push @result, \@usages;
        }
    }

    return \@result;
}

#
# parse_xml($xml_text)
# parse xml text from Merriam_Webster API
sub parse_xml {
    my $xml_text = shift;

    my $dom = XML::LibXML->load_xml(string => $xml_text);

    if ($@) {
        die "Error parsing xml:\n$@";
    }

    print_log("Parse XML:");
    print_log($xml_text);

    $num_defs = 0;

    foreach my $entry ($dom->findnodes('//entry')) {
        undef my %rst;

        $rst{word} = $entry->findvalue('./@id');
        print_log("word: $rst{word}");

        # pronunciation
        @{$rst{prons}} = ();
        if (my $p = $entry->findvalue('./pr')) {
            push @{$rst{prons}}, $p;
        }
        if (my $p = $entry->findvalue('./altpr')) {
            push @{$rst{prons}}, split ',', $p;
        }
        print_log("pronunciation: @{$rst{prons}}");

        # part of speech
        $rst{part_of_speech} = $entry->findvalue('./fl');
        print_log("part of speech: $rst{part_of_speech}");

        # inflections
        @{$rst{inflections}} = ();
        foreach my $inf ($entry->findnodes('./in')) {
            my $tmp = $inf->findvalue('./if');
            $tmp =~ s/\*//g;
            push @{$rst{inflections}}, $tmp;
        }
        print_log("inflections: @{$rst{inflections}}");

        print_log("definition:");
        # grammar
        $rst{gram} = $entry->findvalue('./def/gram');
        print_log("\tgram: $rst{gram}");

        # definition (multidimentional reference array)
        # (
        #   &( # definition block
        #       &(def, e.g., e.g. ...),
        #       &(usage, e.g. ...),
        #   ),
        #   &(
        #       ...
        #   ) ...
        # )
        @{$rst{definitions}} = ();
        foreach my $def_block ($entry->findnodes('./def/dt')) {
            my $d_ref = find_def($def_block);
            if (@{$d_ref}) {
                push @{$rst{definitions}}, $d_ref;
            }
        }
        print_log(Dumper \@{$rst{definitions}});

        # phrases
        # (
        #   (
        #       phrase_body,
        #       &(
        #           &(def, e.g. ...),
        #           &(usage, e.g. ...),
        #           ...
        #       )
        #       ...
        #   )
        # )
        @{$rst{phrases}} = ();
        foreach my $phrase_block ($entry->findnodes('./dro')) {
            my @phrase = ();
            my $p = $phrase_block->findvalue('./dre');
            push @phrase, $p;

            foreach my $def_block ($phrase_block->findnodes('./def/dt')) {
                my $d_ref = find_def($def_block);
                if (@{$d_ref}) {
                    push @phrase, $d_ref;
                }
            }
            push @{$rst{phrases}}, \@phrase;
        }
        print_log(Dumper \@{$rst{phrases}});

        if ($save_to_quizlet) {
            format_word_quizlet(\%rst);
        }
        format_word_output(\%rst);
    }

    if ($save_to_quizlet) {
        print $quizlet_fh "---\n";
    }
}

# merriam_webster($is_learner, $word);
# try to show merriam webster learner and collegiate dictionary
#
# $is_learner:
#   0 - Collegiate dictionary
#   1 - Learner dictionary
# $word:
#   the word want to search
sub merriam_webster {
    my $is_learner = shift;
    my $word = shift;

    # Construcate URL
    my $url = $URL_M_W_API_PART_A;
    if ($is_learner) {
        $url .= ($URL_M_W_API_PART_B_LEARNER . $word . $URL_M_W_API_PART_C . $M_W_LEARNER_API_KEY);
    } else {
        $url .= ($URL_M_W_API_PART_B_COLLEGIATE . $word . $URL_M_W_API_PART_C. $M_W_COLLEGIATE_API_KEY);
    }

    my $response = $ua->get($url);

    if ($response->is_success) {
        my $res_header = $response->header("Content-Type");
        if ($res_header eq "xml") {
            parse_xml($response->decoded_content);
        } else {
            print $less_fh "Not XML\n";
        }
    } else {
        print $less_fh "Merriam Webster Dictionary is not available\n";
        print $less_fh $response->status_line, "\n";
    }
}

sub parse_oxford_json {
    my $text = shift;

    print_log("Parse Json: \n");
    print_log($text);
    
    utf8::encode($text);
    my $decoded_text = decode_json $text;

    foreach my $results_hash (@{$decoded_text->{results}}) {
        foreach my $lexical_entry_ref ($results_hash->{lexicalEntries}) {

            print $lexical_entry_ref;
            print Dumper $lexical_entry_ref;

            my %rst = {};
            # word
            $rst{word} = @$lexical_entry_ref->{text};
            print_log("word: $rst{word}");

            # pronunciation
            @{$rst{prons}} = ();
            my @ps = $lexical_entry_ref->{prounciations};
            if (@ps) {
                foreach my $p (@ps) {
                    push @{$rst{prons}}, $p->{phoneticSpelling};
                }
            }
            print_log("pronunciation: @{$rst{prons}}");

            # part of speech
            $rst{part_of_speech} = $lexical_entry_ref->{lexicalCategory};
            print_log("part of speech: $rst{part_of_speech}");

            format_word_output(\%rst);
        }
    }
}

sub oxford {
    my $word = shift;

    # Oxford API using cURL
    my $url = $URL_OXFORD_API_ENTRY . $word;
    my $cmd = "curl -s -X GET --header 'Accept: application/json'";
    $cmd .= " --header 'app_id: " . $OXFORD_API_APP_ID . "'";
    $cmd .= " --header 'app_key: " . $OXFORD_API_APP_KEY . "'";
    $cmd .= " " . $url;

    my $response = `$cmd`;

    if ($response ne '-1') {
        parse_oxford_json($response);
    } else {
        print $less_fh "Oxford Dictionary is not available\n";
    }
}

#
# show word($api, $word)
# show definitions of the word
# $api:
#   API to call, possible values:
#       - "Oxford"
#       - "Merriam_Webster_Learner"
#       - "Merriam_Webster_Collegiate"
# $word:
#   the word want to search
sub show_word {
    my $dict = shift;
    my $word = shift;

    print $less_fh colored($DICTIONARY_DELIMITER, $COLOUR_DELIMITER);
    print $less_fh colored("| " . $dict . "\n", $COLOUR_DICT);
    print $less_fh colored($DICTIONARY_DELIMITER, $COLOUR_DELIMITER);
    print_log($dict . "\n");

    if ($dict eq $DICT_OXFORD) {
        oxford($word);
    } elsif ($dict eq $DICT_M_W_LEARNER) {
        merriam_webster(1, $word);
    } elsif ($dict eq $DICT_M_W_COLLEGIATE) {

        # do not save Collegiate dictionary to quizlet_fh
        if ($save_to_quizlet) {
            $save_to_quizlet = 0;
        }

        merriam_webster(0, $word);
    }
}

# read_api_key()
# read all api keys from file
sub read_api_key {
    local $/ = undef;
    open my $api_json_fh, '<:encoding(UTF-8)', 'api.json';
    my $json_text = <$api_json_fh>;
    close $api_json_fh;

    my $decoded_text = decode_json $json_text;
    $M_W_LEARNER_API_KEY = $decoded_text->{Merriam_Webster_Learner_Key};
    $M_W_COLLEGIATE_API_KEY = $decoded_text->{Merriam_Webster_Collegiate_Key};
}


sub init {
    # open user agent
    $ua = LWP::UserAgent->new(keep_alive => 1);

    # open log file
    open($log_fh, '>:encoding(UTF-8)', $LOG_FILENAME) or die "Failed to open log file: $!";

    # read api from file
    read_api_key();

    # read searched words and add to set, if the file is not exisit, create it
    unless(-e $SEARCHED_FILENAME) {
        open $searched_fh, '>:encoding(UTF-8)', $SEARCHED_FILENAME;
        close $searched_fh;
    }
    open $searched_fh, '<:encoding(UTF-8)', $SEARCHED_FILENAME or die "$0 open searched_fh: $!";
    while (my $word = <$searched_fh>) {
        chomp $word;
        $searched_words->insert($word);
    }
    close($searched_fh);

    # open searched file for appending
    open $searched_fh, '>>:encoding(UTF-8)', $SEARCHED_FILENAME or die "$0 open quizlet_fh: $!";

    # open quizlet file to append, if not exisit, create
    unless(-e $QUIZLET_FILENAME) {
        open $quizlet_fh, '>:encoding(UTF-8)', $QUIZLET_FILENAME;
        close $quizlet_fh;
    }
    open $quizlet_fh, '>>:encoding(UTF-8)', $QUIZLET_FILENAME or die "$0 open quizlet_fh: $!";
}
##############################
# Main
#

init();
blue_search;
while (<STDIN>) {
    chomp;
    my @s = split;
    if (@s != 1) {
        print $output_fh colored("Please input a word", 'red'), "\n";
    } else {
        # open less, set tabsize to 4
        open $less_fh, '|-:encoding(UTF-8)', 'less -Rc -x4' or die "$0 open less: $!";
        # $less_fh = *STDOUT;

        # lowercase
        my $word = lc $s[0];

        if ($searched_words->has($word)) {
            $save_to_quizlet = 0;
        } else {
            $save_to_quizlet = 1;
            $searched_words->insert($word);
            print $searched_fh $word . "\n";
            print $quizlet_fh $word . "\$\n";
        }

        print_log("Looking up word: " . colored("$word", 'yellow'));

        show_word($DICT_M_W_LEARNER, $word);
        show_word($DICT_M_W_COLLEGIATE, $word);
        # show_word($DICT_OXFORD, $word);

        close($less_fh);
    }

    print $output_fh "\n";

    blue_search;
}

close($searched_fh);
close($quizlet_fh);
close($log_fh);
