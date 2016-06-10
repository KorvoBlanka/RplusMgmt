package RplusMgmt::Controller::API::Options;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Account;
use Rplus::Model::Account::Manager;
use Rplus::Model::Option;
use Rplus::Model::Option::Manager;

use JSON;


sub list {
    my $self = shift;

    my $category = $self->param('category');
    my $acc_id = $self->session('account')->{id};
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

    my $acc_id = $self->session('account')->{id};
    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();

    return $self->render(json => {error => 'Not Found'}, status => 404) unless $options;

    my $opt = from_json($options->{options});
    while (my ($key, $value) = each %$opt_hash) {

        if ($opt->{$category}) {
            $opt->{$category}->{$key} = $value;
        } else {
            $opt->{$category} = {
                $key => $value,
            };
        }
    }

    $options->options(encode_json($opt));
    $options->save;

    return $self->render(json => {status => 'success', options => $opt->{$category}});
}

sub set {
    my $self = shift;

    my $category = $self->param('category');
    my $name = $self->param('name');
    my $val = $self->param('value');

    my $acc_id = $self->session('account')->{id};
    my $options = Rplus::Model::Option->new(account_id => $acc_id)->load();

    return $self->render(json => {error => 'Not Found'}, status => 404) unless $options;

    my $opt = from_json($options->{options});
    if ($opt->{$category}) {
        $opt->{$category}->{$name} = $val;
    } else {
        $opt->{$category} = {
            $name => $val,
        };
    }
    $options->options(encode_json($opt));
    $options->save;

    return $self->render(json => {status => 'success'});
}

sub get_company_name {
    my $self = shift;

    my $acc_id = $self->session('account')->{id};
    my $account = Rplus::Model::Account::Manager->get_objects(query => [id => $acc_id,])->[0];

    return $self->render(json => {status => 'success', name => $account->company_name});
}

sub set_company_name {
    my $self = shift;
    my $name = $self->param('name');

    my $acc_id = $self->session('account')->{id};
    my $account = Rplus::Model::Account::Manager->get_objects(query => [id => $acc_id,])->[0];

    $account->company_name($name);
    $account->save(changes_only => 1);

    return $self->render(json => {status => 'success', name => $account->company_name});
}

1;
