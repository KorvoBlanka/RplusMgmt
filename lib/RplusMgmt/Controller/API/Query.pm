package RplusMgmt::Controller::API::Query;

use Mojo::Base 'Mojolicious::Controller';

use JSON;

use Rplus::Model::AddressObject;
use Rplus::Model::AddressObject::Manager;
use Rplus::Model::QueryCompletion;
use Rplus::Model::QueryCompletion::Manager;

sub auth {
    my $self = shift;
    return 1;
}

sub complete {
    my $self = shift;

    my $q = $self->param('q');
    my $limit = $self->param('limit') || 10;

    return $self->render(json => []) unless $q;

    my @terms = split /\W/, $q;
    my $term = $terms[$#terms];

    my %vals;

    my $qc_iter = Rplus::Model::QueryCompletion::Manager->get_objects_iterator(
        query => [value => {like => lc($term =~ s/([%_])/\\$1/gr).'%'}],
        limit => $limit,
    );
    while (my $qc = $qc_iter->next) {
        $vals{$qc->value} = 1;
    }

    my $addrobj_iter = Rplus::Model::AddressObject::Manager->get_objects_iterator(
        query => [[\'lower(name) LIKE ?' => lc($term =~ s/([%_])/\\$1/gr).'%'], level => 7, curr_status => 0],
        #sort_by => 'level DESC',
        limit => $limit,
    );
    while (my $addrobj = $addrobj_iter->next) {
        $vals{lc($addrobj->name.' '.$addrobj->full_type)} = 1;
    }

    my @res;
    for (keys %vals) {
        my $prefix = $q =~ s/$term\W*$//r;
        push @res, {value => $prefix.$_}; 
        last if @res == $limit;
    }

    return $self->render(json => \@res);
}

1;
