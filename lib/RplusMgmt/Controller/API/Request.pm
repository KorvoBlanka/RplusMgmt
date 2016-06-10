package RplusMgmt::Controller::API::Request;

use Mojo::Base 'Mojolicious::Controller';

use JSON;
use Mojo::Util qw(trim);
use Mojo::Collection;
use Date::Parse;

use Search::Elasticsearch;


no warnings 'experimental::smartmatch';

my $e = Search::Elasticsearch->new();

sub _generate_uid {
    my @chars = ("0".."9");
    my $uid;
    $uid .= $chars[rand @chars] for 1..6;

    return $uid;
}

sub get {
    my $self = shift;

    my $id = $self->param('id');

    my $r = $e->get(
        index => 'rplus',
        type => 'request',
        id => $id,
    );

    return $self->render(json => $r);
}

sub list {
    my $self = shift;

    # Input params
    my $contact_id = $self->param("contact_id");
    my $page = $self->param("page") || 1;
    my $per_page = $self->param("per_page") || 30;

    my $r = $e->search(
        index => 'rplus',
        type => 'request',
        body => {
            size => $per_page,
            from => $per_page * ($page - 1),
            query => {
                bool => {
                    filter => {
                        term => {
                            contact_id => $contact_id,
                        }
                    }
                }
            }
        }
    );

    return $self->render(json => $r);
}

sub save {
    my $self = shift;

    my $data = {};

    my $id = $self->param('id') || _generate_uid();
    $data->{id} = $id;

    $data->{state} = $self->param('state');

    $data->{agent_id} = $self->param('agent');
    $data->{contact_id} = $self->param('contact_id');

    $data->{req_text} = $self->param('req_text');
    $data->{req_bounds} = $self->param('req_bounds');


    my $r = $e->index(
            index   => 'rplus',
            type    => 'request',
            id      => $id,
            body    => $data,
        );

    $r = $e->get(
        index => 'rplus',
        type => 'request',
        id => $id,
    );

    return $self->render(json => $r);
}



1;
