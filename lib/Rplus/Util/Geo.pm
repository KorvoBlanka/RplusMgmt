package Rplus::Util::Geo;

use Rplus::Modern;

use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;

use JSON;
use LWP::UserAgent;

# Геокодирование 2GIS
sub get_coords_by_addr {
    my ($addrobj, $house_num) = @_;

    state $_geocache;

    my ($latitude, $longitude);
    my $q = decode_json($addrobj->metadata)->{'addr_parts'}->[1]->{'name'}.', '.$addrobj->name.', '.$house_num;

    return @{$_geocache->{$q}} if exists $_geocache->{$q};
    if (my $realty = Rplus::Model::Realty::Manager->get_objects(select => ['id', 'latitude', 'longitude'], query => [address_object_id => $addrobj->id, house_num => $house_num, '!latitude' => undef, '!longitude' => undef], limit => 1)->[0]) {
        return latitude => $realty->latitude, longitude => $realty->longitude;
    }

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
            my $data = decode_json($response->decoded_content);
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
