package Rplus::Util::Config;

use Mojo::Asset::File;

my $config_path = '../../app.conf';

sub get_config {
    my $file = Mojo::Asset::File->new(path => $config_path);
    my $config = eval $file->slurp;
    return $config;
}

1;
