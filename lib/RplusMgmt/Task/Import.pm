package RplusMgmt::Task::Import;

use Rplus::Modern;

use Rplus::Model::Media::Manager;
use Rplus::Model::Variable::Manager;
use Rplus::Util::Realty qw(put_object);
use Rplus::Util::Mediator qw(add_mediator);
use Rplus::Util::PhoneNum;

use JSON;
use Data::Dumper;

my $ua = Mojo::UserAgent->new;

sub run {
    my $c = shift;

    my $media_dict = {};
    my $media_iter = Rplus::Model::Media::Manager->get_objects_iterator(query => [type => 'import']);
    while (my $media = $media_iter->next) {
        $media_dict->{$media->code} = $media->id;
    }

    my $last_id = _get_last_id();
    my $max_id = 0;

    my $url = $c->config->{import_server_url} . '/api/result/get';
    my $location_short = 'msk';

    my $page = 0;
    my $quit = 0;
    my $count = 0;
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
            if ($res->json->{count} == 0) {$quit = 1;}
            for my $data (@$realty_data) {
                my $object = from_json($data->{data});

                if ($data->{id} > $max_id) {
                    $max_id = $data->{id};
                }

                $object->{source_media_id} = $media_dict->{$object->{source_media}};
                delete $object->{source_media};

                $count ++;
                say Dumper $object;
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
                    say 'mediator: ' . $mediator_company;
                    foreach (@{$object->{'owner_phones'}}) {
                        say 'add mediator ' . $_;
                        add_mediator($mediator_company, $_);
                    }
                }

                put_object($object, $c->config);
            }
        }
    }

    if ($max_id > $last_id) {
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
