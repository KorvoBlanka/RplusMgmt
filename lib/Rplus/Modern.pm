package Rplus::Modern;

use v5.18;

use strict;
use warnings;
use utf8;

use mro     ();
use feature ();

# Вывод сообщений Data::Dumper на русском языке
use Data::Dumper;
$Data::Dumper::Useqq = 1;
{
    no warnings 'redefine';
    sub Data::Dumper::qquote {
        my $s = shift;
        return "'$s'";
    }
    use warnings 'redefine';
}

binmode STDIN, ':utf8';
binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';

sub import {
    strict->import();
    warnings->import();
    utf8->import();
    feature->import(':5.18');
    mro::set_mro(scalar caller(), 'c3');
}

sub unimport {
    strict->unimport;
    warnings->unimport;
    feature->unimport;
    utf8->unimport;
}

1;
