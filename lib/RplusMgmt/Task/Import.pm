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
    if (!$rt_param) {
        Rplus::Model::RuntimeParam->new(key => 'tasks_run_mutex', value => '{"last_id": 0}')->save; # Create record
    
    } else {
        $last_id = from_json($rt_param->{value})->{last_id};
    }
    say $last_id;
    
    my $tx = $ua->get("http://192.168.5.1:3000/api/realty/list?last_id=$last_id");
    if (my $res = $tx->success) {
        my $realty_data = $res->json->{list};
REALTY:     for my $data (@$realty_data) {
            if ($last_id < $data->{id}) {
                $last_id = $data->{id};
                $rt_param->value("{\"last_id\": $last_id}");
                $rt_param->save;
            }
            
            for (@{$data->{'owner_phones'}}) {
                if(exists $MEDIATOR_PHONES{$_}) {
                  say "mediator: $_";
                  next REALTY;
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
            } or do {
                say $@;
            };
            
        }
    }
    say 'last_id: ' . $last_id;
}

1;
