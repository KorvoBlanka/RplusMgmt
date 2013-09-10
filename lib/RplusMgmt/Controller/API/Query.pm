package RplusMgmt::Controller::API::Query;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Object::Query;
use Rplus::Object::Query::Manager;

use JSON;

sub auth {
    my $self = shift;

    return 1;

    $self->render_not_found;
    return undef;
}

sub complete {
    my $self = shift;

    my $term = $self->param('term');
    my $profile = $self->param('profile');
    my $subquery = $self->param('subquery');

    my @items = Rplus::Object::Query->__complete__($term, profile => $profile, city_id => 3, limit => 10);
    @items = map { { label => $_->{'text'}, value => { field => $_->{'field'}, value => $_->{'value'} } } } @items;

    return $self->render_json(\@items);
}

1;
