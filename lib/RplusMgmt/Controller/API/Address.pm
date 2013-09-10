package RplusMgmt::Controller::API::Address;

use Mojo::Base 'Mojolicious::Controller';

use JSON;

use Rplus::Model::AddressObject;
use Rplus::Model::AddressObject::Manager;

sub auth {
    my $self = shift;
    return 1;
}

sub complete {
    my $self = shift;

    my $term;
    if ($term = $self->param('term')) {
        $term =~ s/([%_])/\\$1/g;
        $term = lc($term);
    }
    my $limit = $self->param('limit') || 10;

    return $self->render(json => []) unless $term;

    my @res;
    my $addrobj_iter = Rplus::Model::AddressObject::Manager->get_objects_iterator(
        query => [[\'lower(expanded_name) LIKE ?' => $term.'%'], curr_status => 0],
        sort_by => 'level DESC',
        limit => $limit,
    );
    while (my $addrobj = $addrobj_iter->next) {
        my $metadata = decode_json($addrobj->metadata);
        push @res, {
            id => $addrobj->id,
            name => $addrobj->name,
            short_type => $addrobj->short_type,
            expanded_name => $addrobj->expanded_name,
            addr_parts => $metadata->{'addr_parts'},
        };
    }

    return $self->render(json => \@res);
}

1;
