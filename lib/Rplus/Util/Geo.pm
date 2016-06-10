package Rplus::Util::Geo;

use Rplus::Modern;

use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;

use JSON;
use LWP::UserAgent;

my $ua = Mojo::UserAgent->new;
$ua->max_redirects(4);

sub get_location_metadata {
  # Input params
  my ($lat, $lng) = @_;

  # Perform reverse geocoding

  my $res = $ua->get(
      'https://geocode-maps.yandex.ru/1.x/?format=json&geocode=' . $lng . ',' . $lat . '&key=AHRyt0oBAAAAWyicdAIAGkJ4VW61SHm2C39aWWNEBX0Ppf8AAAAAAAAAAACl2Ft6tPAwl73mh2D-gxCQ089Xsw==',
      {}
  )->res->json;

  my $a = $res->{response}->{GeoObjectCollection}->{featureMember};

  my @districts = ();
  foreach (@{$a}) {
    if ($_->{GeoObject}->{metaDataProperty}->{GeocoderMetaData}->{kind} eq 'district') {
      push @districts, $_->{GeoObject}->{name};
    }
  }

  @districts = reverse @districts;

  # Locate nearby pois

  my $res = $ua->get(
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=' . $lat . ',' . $lng . '&radius=500&types=point_of_interest&name=&key=AIzaSyAi9zTbzWtEhLVZ8syBV6l7d3QMNLRokVY',
      {}
  )->res->json;

  $a = $res->{results};

  my @pois = ();
  foreach (@{$a}) {
    push @pois, $_->{name};
  }

  return {district => \@districts, pois => \@pois};
}

# Геокодирование google
sub get_coords_by_addr {
    my ($locality, $address, $house_num) = @_;

    state $_geocache;

    my ($latitude, $longitude);
    my $q = $locality . ', ' . $address .', '.$house_num;

    return @{$_geocache->{$q}} if exists $_geocache->{$q};
    if (my $r = Rplus::Model::Realty::Manager->get_objects(
      select => ['id', 'latitude', 'longitude'],
      query => [locality => $locality, address => $address, house_num => $house_num, '!latitude' => undef, '!longitude' => undef],
      limit => 1)->[0]
    ) {
        return latitude => $r->latitude, longitude => $r->longitude;
    }

    my $res = $ua->get(
        'https://geocode-maps.yandex.ru/1.x/?geocode=' . $q . '&format=json',
        {}
    )->res->json;

    if ($res && $res->{response}->{GeoObjectCollection}->{metaDataProperty}->{GeocoderResponseMetaData}->{found} > 0) {

      my @pos = split / /, $res->{response}->{GeoObjectCollection}->{featureMember}->[0]->{GeoObject}->{Point}->{pos};

      $latitude = $pos[1];
      $longitude = $pos[0];
      $_geocache->{$q} = [latitude => $latitude, longitude => $longitude];
    }

    return ($latitude && $longitude ? (latitude => $latitude, longitude => $longitude) : ());
}

sub get_coords_by_addr_google {
    my ($locality, $address, $house_num) = @_;

    state $_geocache;

    my ($latitude, $longitude);
    my $q = $locality . ', ' . $address .', '.$house_num;

    return @{$_geocache->{$q}} if exists $_geocache->{$q};
    if (my $r = Rplus::Model::Realty::Manager->get_objects(
      select => ['id', 'latitude', 'longitude'],
      query => [locality => $locality, address => $address, house_num => $house_num, '!latitude' => undef, '!longitude' => undef],
      limit => 1)->[0]
    ) {
        return latitude => $r->latitude, longitude => $r->longitude;
    }

    my $ua = LWP::UserAgent->new;
    my $response = $ua->post(
        'https://maps.googleapis.com/maps/api/geocode/json',
        [
            address => $q,
            key => 'AIzaSyAi9zTbzWtEhLVZ8syBV6l7d3QMNLRokVY',
        ],
    );
    if ($response->is_success) {
        eval {
            my $data = from_json($response->decoded_content);

            return unless $data->{'status'} ne 'OK';
            if (my $loc = $data->{'results'}->[0]->{'geometry'}->{'location'}) {
                ($longitude, $latitude) = ($loc->{'lng'}, $loc->{'lat'});
                $_geocache->{$q} = [latitude => $latitude, longitude => $longitude];
            }
        } or do {};
    } else {
        say "Invalid response (q: $q)";
    }

    return ($latitude && $longitude ? (latitude => $latitude, longitude => $longitude) : ());
}

# Геокодирование
sub get_coords_by_addr_2gis {
    my ($city, $addr, $house_num) = @_;

    state $_geocache;

    my ($latitude, $longitude);
    my $q = $city . ', ' . $addr . ', ' . $house_num;

    my $ua = LWP::UserAgent->new;
    my $response = $ua->post(
        'http://catalog.api.2gis.ru/geo/search',
        [
            q => $q,
            key => 'rujrdp3400',
            version => '1.3',
            output => 'json',
            types => 'house',
        ],
        Referer => 'http://catalog.api.2gis.ru/',
    );
    if ($response->is_success) {
        eval {
            my $data = from_json($response->decoded_content);
            return unless $data->{'total'};
            if (my $centroid = $data->{'result'}->[0]->{'centroid'}) {
                if ($centroid =~ /^POINT\((\d+\.\d+) (\d+\.\d+)\)$/) {
                    ($longitude, $latitude) = ($1, $2);
                    $_geocache->{$q} = [latitude => $latitude, longitude => $longitude];
                }
            }
            1;
        } or do {};
    } else {
        say "2GIS Invalid response (q: $q)";
    }

    return ($latitude && $longitude ? (latitude => $latitude, longitude => $longitude) : ());
}

1;
