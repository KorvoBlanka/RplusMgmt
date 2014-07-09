package RplusMgmt::Controller::API::Options;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;

use JSON;


sub list {
    my $self = shift;

    my $category = $self->param('category');

    my $rt_param = Rplus::Model::RuntimeParam->new(key => $category)->load();
    my $val = {};
    if ($rt_param) {
        $val = from_json($rt_param->{value});
    }

    my $res = {
        val => $val,
    };

    return $self->render(json => $res);    
}

sub set_multiple {
    my $self = shift;

    my $category = $self->param('category');    
    my $opt_string = $self->param('opt_string');
    my $opt_hash = from_json($opt_string);

    my $rt_param = Rplus::Model::RuntimeParam->new(key => $category)->load();
    
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $rt_param;

    my $vals = from_json($rt_param->{value});
    while (my ($key, $value) = each %$opt_hash) {
        $vals->{$key} = $value;
    }

    $rt_param->value(encode_json($vals));
    $rt_param->save;
    
    return $self->render(json => {status => 'success'});    
}

sub set {
    my $self = shift;

    my $category = $self->param('category');    
    my $name = $self->param('name');
    my $val = $self->param('value');

    my $rt_param = Rplus::Model::RuntimeParam->new(key => $category)->load();
    
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $rt_param;

    my $vals = from_json($rt_param->{value});
    $vals->{$name} = $val;
    $rt_param->value(encode_json($vals));
    $rt_param->save;
    
    return $self->render(json => {status => 'success'});
}

1;
