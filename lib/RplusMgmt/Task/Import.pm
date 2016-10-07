package RplusMgmt::Task::Import;

use Mojo::Log;

use Rplus::Modern;

use Rplus::Model::Media::Manager;
use Rplus::Model::Variable::Manager;
use Rplus::Util::Realty qw(put_object);
use Rplus::Util::Mediator qw(add_mediator);
use Rplus::Util::PhoneNum;
use Rplus::Util::Config qw(get_config);

use JSON;
use Data::Dumper;

my $ua = Mojo::UserAgent->new;

sub run {
    my $log = shift;
    my $config = get_config();

    my $media_dict = {};
    my $media_iter = Rplus::Model::Media::Manager->get_objects_iterator(query => [type => 'import']);
    while (my $media = $media_iter->next) {
        $media_dict->{$media->code} = $media->id;
    }

    my $last_id = _get_last_id();
    my $max_id = 0;

    $log->info('last_id == ' . $last_id);

    my $url = $config->{import_server_url} . '/api/result/get';
    my $location_short = $config->{location_short};

    my $page = 0;
    my $quit = 0;
    while (!$quit) {
        $page ++;

        my $tx = $ua->get($url, form => {
            location => $location_short,
            page => $page ++,
            first_id => $max_id,
            last_id => $last_id
        });

        if (my $res = $tx->success) {

            my $realty_data = $res->json->{list};
            $log->info('got answer ' . $res->json->{count} . ' obj in packet');
            if ($res->json->{count} == 0) {$quit = 1;}

            for my $data (@$realty_data) {

                eval {
                    my $object = from_json($data->{data});

                    $log->info('processing obj ' . $data->{id});

                    if ($data->{id} > $max_id) {
                        $max_id = $data->{id};
                    }

                    $object->{source_media_id} = $media_dict->{$object->{source_media}};
                    delete $object->{source_media};

                    # cluch for avito
                    if ($object->{source_media_id} == 5 && $object->{add_date}) {
                        # add 8 hours
                        say 'yay! avito cluch';
                        my $parser = DateTime::Format::Strptime->new( pattern => '%FT%T' );
                        my $dt = $parser->parse_datetime($object->{add_date});
                        if ($dt) {
                            $dt->add(hours => 8);
                            $object->{add_date} = $dt->datetime();
                        }
                        say Dumper $data;
                    }

                    my @p_phones;
                    foreach (@{$object->{owner_phones}}) {
                        my $pp = Rplus::Util::PhoneNum::parse($_);
                        push @p_phones, $pp;
                    }
                    $object->{owner_phones} = \@p_phones;

                    my $mediator_company = $object->{mediator_company};
                    if ($mediator_company) {
                        delete $object->{mediator_company};
                    }

                    if ($mediator_company) {
                        foreach (@{$object->{'owner_phones'}}) {
                            add_mediator($mediator_company, $_);
                        }
                    }

                    put_object($object, $config);
                } or do {
                    $log->error($@);
                }
            }
        } else {
            $log->error('unable to get answer from import server');
        }
    }

    if ($max_id > $last_id) {
        $log->info('set last id to ' . $max_id);
        _set_last_id($max_id);
    }

    return;
}

sub _get_last_id {
    my $v = Rplus::Model::Variable::Manager->get_objects(query => [name => 'import_last_id'])->[0];
    return $v->value;
}

sub _set_last_id {
    my $last_id = shift;
    my $v = Rplus::Model::Variable::Manager->get_objects(query => [name => 'import_last_id'])->[0];
    $v->value($last_id);
    $v->save;
}

1;
