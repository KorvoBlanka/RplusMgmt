package Rplus::Util::Geo;

use Rplus::Modern;

use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;

use Mojo::UserAgent;
use JSON;

use Data::Dumper;

my $ua = Mojo::UserAgent->new;
$ua->max_redirects(4);

sub _uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}

sub get_location_metadata {
  # Input params
  my ($lat, $lng, $config) = @_;

  my $k = $lng . ',' . $lat;

  my $res = $ua->get(
      'https://geocode-maps.yandex.ru/1.x/',
      form => {
        format => 'json',
        geocode => $lng . ',' . $lat,
        key => $config->{api_keys}->{yandex}
      }
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

  my $tx = $ua->get(
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json',
      form => {
        language => 'ru',
        location => $lat . ',' . $lng,
        radius => $config->{search}->{radius},
        types => $config->{search}->{poi_types},
        #key => $config->{api_keys}->{google},
        key => 'AIzaSyAL5WfkU-scRALuR-STSvICl77fVJDkmZ4',
      }
  );
  $res = $tx->res->json;

  $a = $res->{results};

  my @pois = ();
  foreach (@{$a}) {
    my $t = $_->{name};
    $t =~ s/\"//g;
    push @pois, $t;
  }

  @pois = _uniq(@pois);

  return {district => \@districts, pois => \@pois};
}

# Геокодирование google
sub get_coords_by_addr {
    my ($locality, $address, $house_num) = @_;

    my ($latitude, $longitude);

    my $q = '';
    {
      if ($locality) {
        $q .= $locality;
      }

      if ($address) {
        $q .= ' ' . $address;
      }

      if ($house_num) {
        $q .= ' ' . $house_num;
      }
    }

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
    }

    return ($latitude && $longitude ? (latitude => $latitude, longitude => $longitude) : ());
}

sub get_coords_by_addr_google {
    my ($locality, $address, $house_num) = @_;

    my ($latitude, $longitude);
    my $q = $locality . ', ' . $address .', '.$house_num;

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
            key => 'AIzaSyBw9CMGQ3BzbCopcUdLeaMsPEUEDWZbCWM',
        ],
    );
    if ($response->is_success) {
        eval {
            my $data = from_json($response->decoded_content);

            return unless $data->{'status'} ne 'OK';
            if (my $loc = $data->{'results'}->[0]->{'geometry'}->{'location'}) {
                ($longitude, $latitude) = ($loc->{'lng'}, $loc->{'lat'});
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
