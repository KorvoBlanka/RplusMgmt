package RplusMgmt::Controller::API::Landmark;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Landmark;
use Rplus::Model::Landmark::Manager;

use Mojo::Util qw(trim);

use JSON;

sub auth {
    my $self = shift;

    my $user_role = $self->session->{'user'}->{'role'};
    if ($user_role && $self->config->{'roles'}->{$user_role}->{'configuration'}->{'landmarks'}) {
        return 1;
    }

    $self->render_not_found;
    return undef;
}

sub list {
    my $self = shift;

    my $type = $self->param('type');
    my $lat = $self->param('lat'); $lat = undef unless $lat && $lat =~ /^\d+\.\d+$/;
    my $lng = $self->param('lng'); $lng = undef unless $lng && $lng =~ /^\d+\.\d+$/;

    my $res = {
        count => 0,
        list => [],
    };

    my @fields = qw(id name);
    my $landmark_iter = Rplus::Model::Landmark::Manager->get_objects_iterator(
        select => [@fields],
        query => [
            type => $type,
            ($lat && $lng ? \"t1.geodata::geography && ST_GeogFromText('SRID=4326;POINT($lng $lat)')" : ()),
            delete_date => undef,
        ],
        sort_by => 'name'
    );
    while (my $landmark = $landmark_iter->next) {
        push @{$res->{'list'}}, {map { $_ => $landmark->$_ } @fields};
        $res->{'count'}++;
    }

    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    my $id = $self->param('id');

    my @fields = qw(id type name keywords add_date change_date metadata);
    my $landmark = Rplus::Model::Landmark::Manager->get_objects(select => [@fields], query => [id => $id, delete_date => undef])->[0];
    return $self->render_not_found unless $landmark;

    return $self->render(json => {map { $_ => $landmark->$_ } @fields});
}

sub save {
    my $self = shift;

    my $id = $self->param('id') || undef;
    my $type = $self->param('type') || undef;
    my $name = trim(scalar $self->param('name')) || undef;
    my $keywords = trim(scalar $self->param('keywords')) || undef;
    my $geojson; eval { $geojson = decode_json(scalar($self->param('geojson'))); };
    my $metadata = $self->param('metadata') || undef;

    my $wkt;
    if ($geojson) {
        my $count = 0;
        for my $f (@{$geojson->{'features'}}) {
            next unless $f->{'geometry'}->{'type'} eq 'Polygon';
            $wkt .= ',' if $count;
            $wkt .= '('.join(',', map { '('.join(',', map { join(' ', grep { /^\d+(?:\.\d+)?$/ } @$_) } @$_).')' } @{$f->{'geometry'}->{'coordinates'}}).')';
            $count++;
        }
    }

    my $landmark;
    if ($id) {
        $landmark = Rplus::Model::Landmark::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
        return $self->render(json => {status => 'failed'}) unless $landmark;
    } else {
        $landmark = Rplus::Model::Landmark->new;
    }

    $landmark->type($type);
    $landmark->name($name);
    $landmark->keywords($keywords);
    if ($wkt) {
        $landmark->geodata("postgis.ST_GeomFromEWKT('SRID=4326;MULTIPOLYGON($wkt)')");
    } else {
        $landmark->geodata(undef);
    }
    $landmark->metadata($metadata);

    eval {
        $landmark->save;
    } or do {
        return $self->render(json => {status => 'failed'});
    };

    return $self->render(json => {status => 'success', data => {id => $landmark->id}});
}

sub delete {
    my $self = shift;

    my $id = $self->param('id');

    my $num_rows_updated = Rplus::Model::Landmark::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $id, delete_date => undef],
    );

    return $self->render(json => {status => 'success'});
}

1;
