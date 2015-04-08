package RplusMgmt::Controller::API::Chat;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Account;
use Rplus::Model::Account::Manager;
use Rplus::Model::User;
use Rplus::Model::User::Manager;
use Rplus::Model::ChatMessage;
use Rplus::Model::ChatMessage::Manager;

use File::Path qw(make_path);
use String::Approx 'aindex';
use JSON;

my $tech_support_id = 1287;

sub _add_to_contact_list {
    my $user_id = shift;
    my $contact_id = shift;

    my $user = Rplus::Model::User::Manager->get_objects(query => [id => $user_id])->[0];

    my @cl = $user->contact_list;
    push @cl, $contact_id;

    $user->contact_list(Mojo::Collection->new(@cl)->compact->uniq);
    $user->save(changes_only => 1);
}

sub post {
    my $self = shift;

    my $to = $self->param('to') || undef;
    my $text = $self->param('text');
    my $attachment = $self->param('attachment');
    my $from = $self->stash('user')->{id};
        
    if ($to && $to != $tech_support_id && $from != $tech_support_id) {
        _add_to_contact_list($to, $from);
        _add_to_contact_list($from, $to);
    }
    
    if ($to == $tech_support_id) {
        _add_to_contact_list($tech_support_id, $from);
    }

    if ($from == $tech_support_id) {
        _add_to_contact_list($tech_support_id, $to);
    }
    
    my $message = Rplus::Model::ChatMessage->new (
        to => $to,
        from => $from,
        message => $text,
        attachment => $attachment,
    );
    $message->save;
    $message->load;
    #$self->message_notification($msg);

    my $res = {
        id => $message->id,
        text => $message->message,
        attachment => $message->attachment,
        to => $message->to,
        from => $message->from,
        ts => $message->add_date,
    };
    
    $self->new_message($message->id, $from, $to);
    
    return $self->render(json => {status => 'success', data => $res});
}

sub list {
    my $self = shift;

    my $from = $self->param('from');

    my $last_id = $self->param('last_id') || 0;
    my $user_id = $self->stash('user')->{id};

    my $res = {
        list => [],
    };
    
     my @query;
    {
        if ($from) {
            push @query, or => [and => [from => $from, to => $user_id], and => [to => $from, from => $user_id],];
        } else {
            push @query, to => undef;
        }
    }
    
    if($from) {
        my $num_rows_updated = Rplus::Model::ChatMessage::Manager->update_objects(
            set => {read => 1},
            where => [from => $from, to => $user_id],
        );
    }
    
    my $message_iter = Rplus::Model::ChatMessage::Manager->get_objects_iterator(
        query => [
            @query,
            id => {
                gt => $last_id,
            }
        ],
        with_objects => ['user'],
        sort_by => 'id DESC'
    );
    
    while (my $message = $message_iter->next) {
        my $x = {
            id => $message->id,
            text => $message->message,
            attachment => $message->attachment,
            to => $message->to,
            from => $message->from,
            ts => $message->add_date,
            from_name => $message->user->name,
        };
        push @{$res->{list}}, $x;
    }
    
    return $self->render(json => {status => 'success', data => $res});
}

sub list_contacts {
    my $self = shift;

    my $res = {
        list => [],
    };
    
    my $user_id = $self->stash('user')->{id};
    my $this_user = Rplus::Model::User::Manager->get_objects(query => [id => $user_id])->[0];
    my $cl = Mojo::Collection->new($this_user->contact_list);
    
    my $x = {
        id => undef,
        name => 'Общий чат',
        role => ' ',
        role_loc => '&nbsp;',
        photo_url => undef,
        direct_photo_url => $self->config->{'assets'}->{'url'} . '/common_chat.png',
        account_id => '',
        unread_count => 0,
        company_name => '&nbsp;',
        online => 1,
        can_remove => 0,
        sort_value => 9001,
    };    
    push @{$res->{list}}, $x;
    
    my $tech_user = Rplus::Model::User::Manager->get_objects(query => [id => $tech_support_id])->[0];
    my $unread_count = Rplus::Model::ChatMessage::Manager->get_objects_count(
        query => [
            from => $tech_user->id,
            to =>$this_user->id,
            read => 0,
        ],
    );
    $x = {
        id => $tech_support_id,     #
        name => 'Тех. поддержка',
        role => ' ',
        role_loc => '&nbsp;',
        photo_url => undef,
        direct_photo_url => $self->config->{'assets'}->{'url'} . '/tech_support.png',
        account_id => '',
        unread_count => $unread_count * 1,
        company_name => '&nbsp;',
        online => $self->is_logged_in($tech_user->id),,
        can_remove => 0,
        sort_value => 9000,
    };    
    push @{$res->{list}}, $x;
    
    return $self->render(json => {status => 'success', data => $res}) unless $cl->size;
    
    my $user_iter = Rplus::Model::User::Manager->get_objects_iterator(
        query => [
            id => [$this_user->contact_list],
            delete_date => undef,
        ],
        with_objects => ['account'],
        sort_by => 'account.id ASC'
    );
    
    while (my $user = $user_iter->next) {
    
        my $unread_count = Rplus::Model::ChatMessage::Manager->get_objects_count(
            query => [
                from => $user->id,
                to =>$this_user->id,
                read => 0,
            ],
        );
    
        my $x = {
            id => $user->id,
            name => $user->name,
            role => $user->role,
            role_loc => $self->ucfloc($user->role),
            photo_url => $user->photo_url ? '/' . $user->account->name . $user->photo_url : '',
            account_id => $user->account_id,
            unread_count => $unread_count * 1,
            company_name => $user->account->company_name ? $user->account->company_name : $user->account->name,
            online => $self->is_logged_in($user->id),
            can_remove => 1,
            sort_value => $unread_count * 1,
        };
        push @{$res->{list}}, $x;
    }
    
    return $self->render(json => {status => 'success', data => $res});
}

sub find_contacts {
    my $self = shift;

    my $q = $self->param('q');

    my $res = {
        list => [],
    };
        
    #my $q_phone;
    #if ($q =~ /^\s*[0-9-]{6,}\s*$/) {
    #   $q_phone = $self->parse_phone_num($q);
    #}

    my @q_phones;
    for my $x (split /[ .,]/, $q) {
        if ($x =~ /^\s*[0-9-]{6,}\s*$/) {
            if (my $phone_num = $self->parse_phone_num($x)) {
                push @q_phones, $phone_num;
            }
        }
    }
    
    my $this_user = Rplus::Model::User::Manager->get_objects(query => [id => $self->stash('user')->{id}])->[0];
    my $cl = Mojo::Collection->new($this_user->contact_list);
    
    my $user_iter = Rplus::Model::User::Manager->get_objects_iterator(
        query => [
            '!id' => [10000, $tech_support_id],
            'account.del_date' => undef,
            delete_date => undef,
        ],
        with_objects => ['account'],
        sort_by => 'account.id ASC'
    );
    
    while (my $user = $user_iter->next) {
    
        my $add_to_result = 0;
        
        for my $q_phone (@q_phones) {
            if ($q_phone eq $user->phone_num || $q_phone eq $self->parse_phone_num($user->public_phone_num)) {
                $add_to_result = 1;
            }
        } 
        
        my @r1 = aindex($q, ($user->name,));
        my @r2 = aindex($q, ($user->public_name,));
        if ($r1[0] >= 0 || $r2[0] >= 0) {
            $add_to_result = 1;
        }
        
        if ($add_to_result) {
            my $x = {
                id => $user->id,
                name => $user->name,
                role => $user->role,
                role_loc => $self->ucfloc($user->role),
                photo_url => $user->photo_url ? '/' . $user->account->name . $user->photo_url : '',
                account_id => $user->account_id,
                company_name => $user->account->company_name ? $user->account->company_name : $user->account->name,
                unread_count => 0,
                online => $self->is_logged_in($user->id) || 0,
                in_contact_list => $cl->first(sub { $_ == $user->id }),
            };
            push @{$res->{list}}, $x;
        }
    }
    
    return $self->render(json => {status => 'success', data => $res});
}

sub add_to_contact_list {
    my $self = shift;

    my $contact_id = $self->param('contact_id');
    my $user_id = $self->stash('user')->{id};
    return $self->render(json => {errors => ['contact_id == user_id', ]}, status => 400) if ($contact_id == $user_id);
    
    my $c = Rplus::Model::User::Manager->get_objects(query => [id => $contact_id], with_objects => ['account'],)->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $c;

    my $user = Rplus::Model::User::Manager->get_objects(query => [id => $user_id])->[0];
    
    my @cl = $user->contact_list;
    
    push @cl, $contact_id;
    
    $user->contact_list(Mojo::Collection->new(@cl)->compact->uniq);
    $user->save;
    
    
    my $data = {
        id => $c->id,
        name => $c->name,
        role => $c->role,
        role_loc => $self->ucfloc($c->role),
        photo_url => $c->photo_url ? '/' . $c->account->name . $c->photo_url : '',
        account_id => $c->account_id,
        unread_count => 0,
        company_name => $c->account->company_name ? $c->account->company_name : $c->account->name,
        online => $self->is_logged_in($c->id),
        can_remove => 1,
        sort_value => 0,
    };
    
    return $self->render(json => {status => 'success', contact => $data});
}

sub remove_from_contact_list {
    my $self = shift;

    my $contact_id = $self->param('contact_id');
    my $user_id = $self->stash('user')->{id};
    
    my $user = Rplus::Model::User::Manager->get_objects(query => [id => $user_id])->[0];
    
    my $cl = Mojo::Collection->new($user->contact_list);
    
    my $ncl = $cl->grep(sub {$_ != $contact_id});
    
    $user->contact_list($ncl);
    $user->save;
    
    return $self->render(json => {status => 'success'});
}

sub get_unread_message_count {
    my $self = shift;
    
    my $user_id = $self->stash('user')->{id};
    my $message_count = Rplus::Model::ChatMessage::Manager->get_objects_count(
        query => [
            to => $user_id,
            read => 0,
        ],
    );
    
    return $self->render(json => {status => 'success', data => {count => $message_count}});
}

sub upload_file {
    my $self = shift;

    my $file_url = '';
    my $cat = '/users/files/';
    
    if (my $file = $self->param('file')) {
    
        say Dumper $file;
    
        my $path = $self->config->{'storage'}->{'path'} . $cat;
        my $name = (Time::HiRes::time =~ s/\.//r) . '_' . $file->filename; # Unique name

        eval {
            make_path($path);
            $file->move_to($path . $name);
            $file_url = $cat . $name;
        } or do {
            return $self->render(json => {error => $@}, status => 500);
        };

        return $self->render(json => {status => 'success', file_url => $self->config->{'storage'}->{'url'} . $file_url});
    }

    return $self->render(json => {error => 'Bad Request'}, status => 400);
}

1;
