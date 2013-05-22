package RplusMgmt::Controller::API::Street;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Street;
use Rplus::Model::Street::Manager;

sub auth {
    my $self = shift;

    return 1;

    $self->render_not_found;
    return undef;
}

sub complete {
    my $self = shift;

    # TODO: Хабаровск (!)
    my $city_id = $self->param('city_id') || 3;

    my $term;
    if ($term = $self->param('term')) {
        $term =~ s/([%_])/\\$1/g;
        $term = lc($term);
    }

    my $per_page = $self->param('per_page') || 10;
    my $page = $self->param('page'); $page = 1 unless $page && $page > 0;

    my $res = {
        count => Rplus::Model::Street::Manager->get_objects_count(query => [ parent_kladr_id => $city_id, ($term ? (name_lc => { like => $term.'%' }) : ()) ]),
        list => []
    };
    my $street_iter = Rplus::Model::Street::Manager->get_objects_iterator(
        select => 'id, name, name2',
        query => [ parent_kladr_id => $city_id, ($term ? (name_lc => { like => $term.'%' }) : ()) ],
        sort_by => 'name',
        per_page => $per_page,
        page => $page,
    );
    while (my $street = $street_iter->next) {
        push @{$res->{'list'}}, {
            id => $street->id,
            text => $street->name2,
        };
    }

    $res->{'page'} = $page;
    if ($res->{'count'}) {
        $res->{'prev'} = $page - 1 if $page > 1;
        $res->{'next'} = $page + 1 if $res->{'count'} > $page * $per_page;
    }

    return $self->render_json($res);
}

1;
