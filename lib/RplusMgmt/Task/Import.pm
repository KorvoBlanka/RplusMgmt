package RplusMgmt::Task::Import;

use Rplus::Modern;

use Rplus::Model::Media::Manager;
use Rplus::Model::Variable::Manager;

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

        say '<<<<<<<<<<<<<<<<<<<';
        say $max_id;
        say $last_id;
        sleep 1;

        my $tx = $ua->get($url, form => {
            location => $location_short,
            page => $page ++,
            first_id => $max_id,
            last_id => $last_id
        });

        if (my $res = $tx->success) {

            my $realty_data = $res->json->{list};
            say 'ld count ' . $res->json->{count};
            if ($res->json->{count} == 0) {$quit = 1;}
            for my $data (@$realty_data) {
                my $object = from_json($data->{data});

                say 'max_id ' . $max_id;
                if ($data->{id} > $max_id) {
                    say 'max_id ' . $max_id;
                    $max_id = $data->{id};
                }

                $object->{source_media_id} = $media_dict->{$object->{source_media}};
                delete $object->{source_media};

                say '!';
                $count ++;
                #say Dumper $object;

                #sleep 1;
            }
        }
    }

    if ($max_id > $last_id) {
        _set_last_id($max_id);
    }

    say 'done ' . $count;

    return;
}

sub _get_last_id {
    my $v = Rplus::Model::Variable::Manager->get_objects(query => [name => 'import_last_id'])->[0];
    return $v->value;
}

sub _set_last_id {
    my $last_id = shift;
    my $v = Rplus::Model::Variable::Manager->get_objects(query => [name => 'import_last_id'])->[0];
    $v->value($max_id);
    $v->save;
}

1;
