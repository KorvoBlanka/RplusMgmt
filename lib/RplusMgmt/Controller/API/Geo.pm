package RplusMgmt::Controller::API::Geo;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::MapHouse;
use Rplus::Model::MapHouse::Manager;
use Rplus::Model::Sublandmark;
use Rplus::Model::Sublandmark::Manager;

use Mojo::Util qw(xml_escape);
use Rplus::Util qw(format_house_num);

sub auth {
    my $self = shift;

    return 1;

    $self->render_not_found;
    return undef;
}

sub get {
    my $self = shift;

    my $street_id = $self->param('street_id');
    my $house_num = format_house_num(scalar($self->param('house_num')));
    return $self->render_json({status => 'failed'}) unless $street_id && $house_num;

    my $map_house = Rplus::Model::MapHouse::Manager->get_objects(query => [ street_id => $street_id, house_num => $house_num ])->[0];
    return $self->render_json({status => 'failed'}) unless $map_house;

    my @sublandmarks;
    if (@{$map_house->sublandmarks}) {
        my $sublandmark_iter = Rplus::Model::Sublandmark::Manager->get_objects_iterator(query => [ id => scalar($map_house->sublandmarks), delete_date => undef ]);
        while (my $sublandmark = $sublandmark_iter->next) {
            push @sublandmarks, {
                id => $sublandmark->id,
                text => xml_escape($sublandmark->name),
            };
        }
    }

    return $self->render_json({
        status => 'success',
        sublandmarks => \@sublandmarks,
        latitude => $map_house->latitude,
        longitude => $map_house->longitude,
    });
}

1;
