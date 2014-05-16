package RplusMgmt::Task::Import;

use Rplus::Modern;

use Rplus::Model::Realty;
use Rplus::Model::Realty::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;

use Rplus::Util::Image;

use JSON;

sub run {
    my $self = shift;
    my $c = shift;
    # Загрузим базу телефонов посредников
    my %MEDIATOR_PHONES;
    {
        my $mediator_iter = Rplus::Model::Mediator::Manager->get_objects_iterator(query => [delete_date => undef], require_objects => ['company']);
        while (my $x = $mediator_iter->next) {
            $MEDIATOR_PHONES{$x->phone_num} = {
                id => $x->id,
                name => $x->name,
                company => $x->company->name,
            };
        }
    }
    my $ua = Mojo::UserAgent->new;    
    
    my $rt_param = Rplus::Model::RuntimeParam->new(key => 'import_param')->load();
    my $last_id = 0;
    my $t_last_id = 0;
    if (!$rt_param) {
        Rplus::Model::RuntimeParam->new(key => 'tasks_run_mutex', value => '{"last_id": 0}')->save; # Create record

    } else {
        $last_id = from_json($rt_param->{value})->{last_id};
        $t_last_id = $last_id;
    }

    #my $rt_param = Rplus::Model::RuntimeParam->new(key => 'opt_var')->load();
    
    my $import_param = Rplus::Model::RuntimeParam->new(key => 'opt_var')->load();
    my $import_obj = from_json($import_param->{value});
    while (my ($key, $value) = each $import_obj) {
        my @t = split '-', $key;
        my $offer_type = $t[0];
        my $source_media = $t[1];
        my $realty_type = $t[2];

        next if $value eq '0';

        say $realty_type;
        
        my $tx = $ua->get("http://192.168.5.1:3000/api/realty/list", form => {last_id => $last_id, offer_type => $offer_type, source_media => $source_media, realty_type => $realty_type});
        if (my $res = $tx->success) {
            my $realty_data = $res->json->{list};
NEXT:       for my $data (@$realty_data) {
                if ($t_last_id < $data->{id}) {
                    $t_last_id = $data->{id};
                    $rt_param->value("{\"last_id\": $t_last_id}");
                    $rt_param->save;                    
                }
    
                for (@{$data->{'owner_phones'}}) {
                    if(exists $MEDIATOR_PHONES{$_}) {
                        if ($data->{offer_type} eq 'rent') {
                          next NEXT;
                        }
                        my $mediator = Rplus::Model::Mediator::Manager->get_objects(query => [phone_num => $_, delete_date => undef], require_objects => ['company'])->[0];
                        $data->{mediator} = $mediator->company->name . '. ' . $mediator->name;
                        $data->{agent_id} = 10000;
                    }
                }
                eval {
                    my $realty = Rplus::Model::Realty->new((map { $_ => $data->{$_} } grep { $_ ne 'category_code' && $_ ne 'id' } keys %$data), state_code => 'raw');
                    $realty->save;
                    my $data_id = $data->{id};
                    my $id = $realty->id;
                    say "Saved new realty: $id";
                    
                    my $tx = $ua->get("http://192.168.5.1:3000/api/realty/get_photos?realty_id=$data_id");
                    if (my $res = $tx->success) {
                        my $photo_data = $res->json->{list};
                        for my $photo (@$photo_data) {
                            say $photo->{photo_url};
                            my $image = $ua->get($photo->{photo_url})->res->content->asset;
                            Rplus::Util::Image::load_image($id, $image, $c->config->{storage}->{path}, 0);
                        }
                    }
                    #$self->realty_event('c', $id);
                    # Сохраним историю
                    if ($id && !Rplus::Model::MediaImportHistory::Manager->get_objects_count(query => [media_id => $data->{source_media_id}, media_num => '', realty_id => $id])) {
                        Rplus::Model::MediaImportHistory->new(media_id => $data->{source_media_id}, media_num => '', media_text => $data->{'source_media_text'}, realty_id => $id)->save;                    
                    }
                } or do {
                    say $@;
                };
                
            }
        }
    }
    say 'last_id: ' . $last_id;
}

1;
