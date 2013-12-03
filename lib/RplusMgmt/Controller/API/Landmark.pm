package RplusMgmt::Controller::API::Landmark;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Landmark;
use Rplus::Model::Landmark::Manager;

use JSON;

sub list {
    my $self = shift;

    # Can be executed by all users

    # Input validation
    $self->validation->required('type');
    $self->validation->optional('lat')->like(/^\d+\.\d+$/);
    $self->validation->optional('lng')->like(/^\d+\.\d+$/);

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {type => 'Invalid value'} if $self->validation->has_error('type');
        push @errors, {lat => 'Invalid value'} if $self->validation->has_error('lat');
        push @errors, {lng => 'Invalid value'} if $self->validation->has_error('lng');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

    # Input params
    my $type = $self->param('type');
    my ($lat, $lng) = $self->param(qw(lat lng));

    my $res = {
        total => 0,
        list => [],
    };

    my $landmark_iter = Rplus::Model::Landmark::Manager->get_objects_iterator(
        select => [qw(id name type add_date change_date grp grp_pos)],
        query => [
            type => $type,
            ($lat && $lng ? \"t1.geodata::geography && ST_GeogFromText('SRID=4326;POINT($lng $lat)')" : ()),
            delete_date => undef,
        ],
        sort_by => 'name'
    );
    while (my $landmark = $landmark_iter->next) {
        my $x = {
            id => $landmark->id,
            type => $landmark->type,
            name => $landmark->name,
            add_date => $self->format_datetime($landmark->add_date),
            grp => $landmark->grp,
            grp_pos => $landmark->grp_pos
        };
        push @{$res->{list}}, $x;
    }

    $res->{count} = scalar @{$res->{list}};

    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(landmarks => 'read');

    my $id = $self->param('id');

    my $landmark = Rplus::Model::Landmark::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $landmark;

    my $res = {
        id => $landmark->id,
        type => $landmark->type,
        name => $landmark->name,
        keywords => $landmark->keywords,
        add_date => $landmark->add_date,
        change_date => $landmark->change_date,
        geojson => decode_json($landmark->geojson),
        center => decode_json($landmark->center),
        zoom => $landmark->zoom,
        grp => $landmark->grp,
        grp_pos => $landmark->grp_pos,
    };

    return $self->render(json => $res);
}

sub save {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(landmarks => 'write');

    # Retrieve landmark
    my $landmark;
    if (my $id = $self->param('id')) {
        $landmark = Rplus::Model::Landmark::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    } else {
        $landmark = Rplus::Model::Landmark->new;
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $landmark;

    # Input validation
    $self->validation->required('type');
    $self->validation->required('name');
    $self->validation->required('geojson')->is_json;
    $self->validation->required('center')->is_json;
    $self->validation->required('zoom')->like(qr/^\d+$/);
    $self->validation->optional('grp_pos')->like(qr/^\d+$/);

    if ($self->validation->has_error) {
        my @errors;
        push @errors, {type => 'Invalid value'} if $self->validation->has_error('type');
        push @errors, {name => 'Invalid value'} if $self->validation->has_error('name');
        push @errors, {geojson => 'Invalid JSON object'} if $self->validation->has_error('geojson');
        push @errors, {center => 'Invalid LatLng JSON object'} if $self->validation->has_error('center');
        push @errors, {zoom => 'Invalid value'} if $self->validation->has_error('zoom');
        push @errors, {grp_pos => 'Invalid value'} if $self->validation->has_error('grp_pos');
        return $self->render(json => {errors => \@errors}, status => 400);
    }

    # Input params
    my $type = $self->param('type');
    my $name = $self->param_n('name');
    my $keywords = $self->param_n('keywords');
    my $geojson; eval { $geojson = decode_json(scalar $self->param('geojson')); };
    my $center; eval { $center = decode_json(scalar $self->param('center')); };
    my $zoom = $self->param('zoom');
    my $grp = $self->param_n('grp');
    my $grp_pos = $self->param_n('grp_pos');

    # Save
    $landmark->type($type);
    $landmark->name($name);
    $landmark->keywords($keywords);
    $landmark->geojson(encode_json($geojson));
    $landmark->center(encode_json($center));
    $landmark->zoom($zoom);
    $landmark->grp($grp);
    $landmark->grp_pos($grp_pos);

    eval {
        $landmark->save($landmark->id ? (changes_only => 1) : (insert => 1));
    } or do {
        if ($@ =~ /landmarks_uniq_idx/) {
            return $self->render(json => {errors => [{name => 'Duplicate value'}]}, status => 400);
        }
        return $self->render(json => {error => $@}, status => 500);
    };

    my $wkt;
    if ($geojson) {
        my $count = 0;
        for my $f (@{$geojson->{features}}) {
            next unless $f->{geometry}->{type} eq 'Polygon';
            $wkt .= ',' if $count;
            $wkt .= '('.join(',', map { '('.join(',', map { join(' ', grep { /^\d+(?:\.\d+)?$/ } @$_) } @$_).')' } @{$f->{geometry}->{coordinates}}).')';
            $count++;
        }
    }

    # Set geodata and update change date
    Rplus::Model::Landmark::Manager->update_objects(
        set => {geodata => $wkt ? \"postgis.ST_GeomFromEWKT('SRID=4326;MULTIPOLYGON($wkt)')" : undef, change_date => \'now()'},
        where => [id => $landmark->id],
    );

    return $self->render(json => {status => 'success', id => $landmark->id});
}

sub delete {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(landmarks => 'write');

    my $id = $self->param('id');

    my $num_rows_updated = Rplus::Model::Landmark::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $id, delete_date => undef],
    );
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $num_rows_updated;

    return $self->render(json => {status => 'success'});
}

1;
