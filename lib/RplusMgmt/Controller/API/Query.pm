package RplusMgmt::Controller::API::Query;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Object::Query;
use Rplus::Object::Query::Manager;

use JSON;
use Mojo::Util qw(xml_escape trim);

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
    my $subquery; eval { $subquery = decode_json(scalar($self->param('subquery'))); } or do {};

    my @items = Rplus::Object::Query->complete_params(term => $term, profile => $profile, subquery => $subquery);
    my @items2;
    for (my $i = 0; $i < @items; $i++) {
        my $x = $items[$i];
        if ($x->{'field'} eq 'rooms_count' || $x->{'field'} eq 'price' || $x->{'field'} eq 'floor' || $x->{'field'} eq 'square_total') {
            push @items2, $x;
            $items[$i] = undef;
        }
    }
    push @items2, (sort { length($a->{'label'}) <=> length($b->{'label'}) } grep { defined $_ } @items);
    @items2 = map { { label => xml_escape($_->{'label'}), value => { field => $_->{'field'}, value => $_->{'value'} } } } @items2;

    return $self->render_json(\@items2);
}

1;
