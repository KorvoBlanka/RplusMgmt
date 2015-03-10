package RplusMgmt::Controller::API::Options;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Option;
use Rplus::Model::Option::Manager;

use JSON;


sub list {
    my $self = shift;

    my $category = $self->param('category');
    my $acc_id = $self->session('user')->{account_id};
    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    my $opt = {};
    if ($options) {
        $opt = from_json($options->{options});
    }

    my $res = {
        options => $opt->{$category},
    };

    return $self->render(json => $res);    
}

sub set_multiple {
    my $self = shift;

    my $category = $self->param('category');
    my $opt_string = $self->param('opt_string');
    my $opt_hash = from_json($opt_string);

    my $acc_id = $self->session('user')->{account_id};
    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();

    return $self->render(json => {error => 'Not Found'}, status => 404) unless $options;

    my $opt = from_json($options->{options});
    while (my ($key, $value) = each %$opt_hash) {
        $opt->{$category}->{$key} = $value;
    }

    $options->options(encode_json($opt));
    $options->save;
    
    return $self->render(json => {status => 'success'});    
}

sub set {
    my $self = shift;

    my $category = $self->param('category');
    my $name = $self->param('name');
    my $val = $self->param('value');

    my $acc_id = $self->session('user')->{account_id};
    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();
    
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $options;

    my $opt = from_json($options->{options});
    $opt->{$category}->{$name} = $val;
    $options->options(encode_json($opt));
    $options->save;
    
    return $self->render(json => {status => 'success'});
}

1;
