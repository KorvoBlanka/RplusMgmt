package Rplus::Util::Config;

use Cwd qw/abs_path/;
use Mojo::Asset::File;

use Exporter qw(import);
 
our @EXPORT_OK = qw(get_config);

sub get_config {
    # get path to Config.pm, then build a path to app.conf
    my $module = __PACKAGE__;
    $module =~s/::/\//g;
    my $path = $INC{$module . '.pm'};
    $path =~ s{^(.*/)[^/]*$}{$1};
    $path = abs_path($path . '/../../../app.conf');
    
    my $file = Mojo::Asset::File->new(path => $path);
    my $config = eval $file->slurp;
    return $config;
}

1;
