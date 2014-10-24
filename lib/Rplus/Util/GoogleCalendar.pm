package Rplus::Util::GoogleCalendar;

use Rplus::Modern;

use Rplus::Model::DictTaskType::Manager;
use Rplus::Model::User::Manager;
use Rplus::Model::Task::Manager;

use Date::Parse;
use Mojo::UserAgent;
use JSON;

use Data::Dumper;

my $CLIENT_ID = '18830375155-q1bh1fhapui07fp7drs6fcgp4vca4hn4.apps.googleusercontent.com';
my $CLIENT_SECRET = 'VZKzvmy9uqJRIx2ziuOFo2xF';
my $REDIRECT_URI = 'http://rplusmgmt.com/api/googleauth/callback';

my $task_types_dict = {};
for my $x (@{Rplus::Model::DictTaskType::Manager->get_objects(query => [delete_date => undef,], sort_by => 'id')}) {
    $task_types_dict->{$x->name} = $x->id;
}

# помогайки для работы с json 
sub getGoogleData {
    my ($user_id) = @_;

    my $user = Rplus::Model::User::Manager->get_objects(query => [id => $user_id, delete_date => undef])->[0];
    return undef unless $user;

    my $data = decode_json $user->google;

    return $data;
}

sub setGoogleData {
    my ($user_id, $data) = @_;

    my $user = Rplus::Model::User::Manager->get_objects(query => [id => $user_id, delete_date => undef])->[0];
    return 0 unless $user;

    $user->google(encode_json $data);
    $user->save(changes_only => 1);

    return 1;
}

sub updateGoogleData {
    my ($user_id, $new_data) = @_;

    my $user = Rplus::Model::User::Manager->get_objects(query => [id => $user_id, delete_date => undef])->[0];
    return 0 unless $user;

    my $data = decode_json $user->google;

    foreach my $key (keys %$new_data) {
        $data->{$key} = $new_data->{$key};
    }

    $user->google(encode_json $data);
    $user->save(changes_only => 1);

    return 1;
}

# сохраняем для user_id полученный токен, считаем что имеем разрешение на доступ к данным
sub setRefreshToken {
    my ($user_id, $refresh_token) = @_;

    my $data = {
        permission_granted => 1,
        refresh_token => $refresh_token,
    };

    return setGoogleData($user_id, $data);
}

# если есть access_token и он истек срое его действия - вернем его, иначе используя refresh_token для user_id, запросим новый
sub getAuthorizationStr {
    my ($user_id) = @_;  

    my $data = getGoogleData($user_id);

    if ($data->{access_token} && $data->{token_type} && $data->{access_token_ts} && $data->{expires_in}) {
        if ($data->{access_token_ts} + $data->{expires_in} > time) {
            say 'reuse token!';
            return $data->{token_type} . ' ' . $data->{access_token};
        }
    } 

    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->post('https://accounts.google.com/o/oauth2/token', {
            'Content-Type' => 'application/x-www-form-urlencoded',
        }, 
        form => {
            client_id => $CLIENT_ID,
            client_secret => $CLIENT_SECRET,      
            grant_type => 'refresh_token',
            refresh_token => $data->{refresh_token},
        }
    );

    my $asset;
    my $new_data = {
        access_token => undef,
        access_token_ts => undef,
        token_type => undef,
        expires_in => undef,
    };

    if (my $res = $tx->success) {
        $asset = decode_json $res->content->asset->{content};
        $new_data->{access_token} = $asset->{access_token};
        $new_data->{access_token_ts} = time . '';
        $new_data->{token_type} = $asset->{token_type};
        $new_data->{expires_in} = $asset->{expires_in};
    }

    updateGoogleData($user_id, $new_data);

    return $new_data->{token_type} . ' ' . $new_data->{access_token};
}

# 
sub sync {
    my ($user_id) = @_;
    my $items = [];

    my $data = getGoogleData($user_id);
    return [] unless $data->{permission_granted};
    my $authorization_str = getAuthorizationStr($user_id);


    my $ua = Mojo::UserAgent->new;
    my $next_page_token = undef;
    my $q_sync_token = $data->{next_sync_token} ? ("&syncToken=" . $data->{next_sync_token}) : '';    
    do {
        my $q_next_page_token = $next_page_token ? "&pageToken=$next_page_token" : '';
        my $tx = $ua->get('https://www.googleapis.com/calendar/v3/calendars/primary/events?singleEvents=true' . $q_sync_token . $q_next_page_token, {
                'authorization' => $authorization_str,
            }
        );

        my $asset;
        if (my $res = $tx->success) {
            my $t_str;
            if ($res->content->asset->{content}) {
                $t_str = $res->content->asset->{content};
            } else {    # ответ "большой", читаем файл
                open FILE, $res->content->asset->{path};
                $t_str = join("", <FILE>);
            }
            $asset = decode_json $t_str;
            $next_page_token = $asset->{nextPageToken};
            if ($asset->{nextSyncToken}) {
                updateGoogleData($user_id, {next_sync_token => $asset->{nextSyncToken}});
            }
            push @$items, @{$asset->{items}};
        } else {
            $next_page_token = undef;
        }
    } while ($next_page_token);

    # перебрать все полученые события и синхронизировать их со своими, вернуть список измененных/добавленных событий
    for my $item (@{$items}) {
        if ($item->{status} eq 'cancelled') {
            my $task = Rplus::Model::Task::Manager->get_objects(query => [google_id => $item->{id}, delete_date => undef])->[0];
            if ($task) {
                $task->status('done');
                $task->save;
            }
        } elsif ($item->{status} eq 'confirmed' || $item->{status} eq 'tentative') {
            my $task_type_id = 6;
            my $summary;
            my $description;
            while (my ($key, $value) = each %$task_types_dict) {
                if ($item->{summary} =~ /^$key/i) {
                    $item->{summary} =~ s/^$key: //i;     # вырежем из описания тип задачи
                    $task_type_id = $value;
                }
            }
            $summary = $item->{summary};
            $description = $item->{description};
            
            # если такого google_id нет - создадим новое событие
            my $task = Rplus::Model::Task::Manager->get_objects(query => [google_id => $item->{id}, delete_date => undef])->[0];
            unless ($task) {
                $task = Rplus::Model::Task->new(task_type_id => $task_type_id, creator_user_id => $user_id, google_id => $item->{id});
            }
            $task->task_type_id($task_type_id);
            $task->assigned_user_id($user_id);
            $task->summary($summary);
            $task->description($description);
            $task->start_date($item->{start}->{dateTime});
            $task->end_date($item->{end}->{dateTime});
            $task->save;
        }
    }

    return $items;
}

sub syncAll {
    my $sync_items = [];
    for my $x (@{Rplus::Model::User::Manager->get_objects(query => [delete_date => undef,], sort_by => 'id')}) {
        my $data = getGoogleData($x->id);
        next unless $data->{permission_granted};
        push @$sync_items, @{sync($x->id)};
    }
    return $sync_items;
}

# добавить задачу для user_id
sub insert {
    my ($user_id, $event_data) = @_;  

    my $data = getGoogleData($user_id);
    return undef unless $data->{permission_granted};
    my $authorization_str = getAuthorizationStr($user_id);

    my $reminder_minutes = int((str2time($event_data->{start_date}) - time()) / 60);
    if ($reminder_minutes > 36000 || $reminder_minutes <= 0) {
        $reminder_minutes = 36000; # гугл не любит уведолять ранее чем за 36000 минут
    }

    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->post('https://www.googleapis.com/calendar/v3/calendars/primary/events?sendNotifications=true', {
            'authorization' => $authorization_str,
        }, json => {
            summary => $event_data->{summary},
            description => $event_data->{description},
            end => {
                dateTime => $event_data->{end_date},
            },
            start => {
                dateTime => $event_data->{start_date},
            },
            reminders => {
                useDefault => 'false',
                overrides => [{
                        method => 'email',
                        minutes => $reminder_minutes,
                    }, {
                        method => 'popup',
                        minutes => $reminder_minutes,
                    }, {
                        method => 'email',
                        minutes => '30',
                    }, {
                        method => 'popup',
                        minutes => '30',
                    },
                ],
            }
        }
    );

    my $asset;
    if (my $res = $tx->success) {
        $asset = decode_json $res->content->asset->{content};
    }

    return $asset;
}

# изменить задачу для user_id
sub patch {
    my ($user_id, $google_id, $event_data) = @_;  

    my $data = getGoogleData($user_id);
    return undef unless $data->{permission_granted};
    my $authorization_str = getAuthorizationStr($user_id);    

    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->patch('https://www.googleapis.com/calendar/v3/calendars/primary/events/' . $google_id, {
            'authorization' => $authorization_str,
        }, json => {
            summary => $event_data->{summary},
            description => $event_data->{description},
            end => {
                dateTime => $event_data->{end_date},
            },
            start => {
                dateTime => $event_data->{start_date},
            }
        }
    );
    
    my $asset;
    if (my $res = $tx->success) {
        $asset = decode_json $res->content->asset->{content};
    }

    return $asset;
}

sub setStatus {
    my ($user_id, $google_id, $status) = @_;  

    my $data = getGoogleData($user_id);
    return undef unless $data->{permission_granted};
    my $authorization_str = getAuthorizationStr($user_id);    

    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->patch('https://www.googleapis.com/calendar/v3/calendars/primary/events/' . $google_id, {
            'authorization' => $authorization_str,
        }, json => {
            status => $status,
        }
    );
    
    my $asset;
    if (my $res = $tx->success) {
        $asset = decode_json $res->content->asset->{content};
    }

    return $asset;  
}

sub setStartEndDate {
    my ($user_id, $google_id, $start_date, $end_date) = @_;  

    my $data = getGoogleData($user_id);
    return undef unless $data->{permission_granted};
    my $authorization_str = getAuthorizationStr($user_id);    

    my $ua = Mojo::UserAgent->new;
    my $tx = $ua->patch('https://www.googleapis.com/calendar/v3/calendars/primary/events/' . $google_id, {
            'authorization' => $authorization_str,
        }, json => {
            end => {
                dateTime => $end_date,
            },
            start => {
                dateTime => $start_date,
            }
        }
    );
    
    my $asset;
    if (my $res = $tx->success) {
        $asset = decode_json $res->content->asset->{content};
    }

    return $asset;  
}

1;