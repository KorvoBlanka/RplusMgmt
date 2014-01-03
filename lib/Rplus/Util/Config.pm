package Rplus::Util::Config;

use Mojo::Asset::File;

sub get_config {
    my $config_path = shift;
    my $file = Mojo::Asset::File->new(path => $config_path);
    my $config = eval $file->slurp;
    return $config;
}

1;
