package Rplus::Util::Config;

use utf8;

use Cwd qw/abs_path/;
use Mojo::Asset::File;

use Exporter qw(import);

our @EXPORT_OK = qw(get_config);

my $default_name = 'app.conf';

sub get_config {
    # get path to Config.pm, then build a path to app.conf
    my $module = __PACKAGE__;
    my $filename = shift;

    $filename = $default_name unless $filename;

    $module =~s/::/\//g;
    my $path = $INC{$module . '.pm'};
    $path =~ s{^(.*/)[^/]*$}{$1};
    $path = abs_path($path . '/../../../' . $filename);

    my $file = Mojo::Asset::File->new(path => $path);
    my $config = eval $file->slurp;
    return $config;
}

1;
