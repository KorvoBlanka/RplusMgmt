package RplusMgmt::Controller::API::Mediator;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Company;
use Rplus::Model::Company::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;

use Rplus::Object::Realty;
use Rplus::Object::Realty::Manager;

use Rplus::DB;
use Rplus::Util qw(format_phone_num);
use Mojo::Util qw(trim);
use List::MoreUtils qw(any);

sub auth {
    my $self = shift;

    my $user_role = $self->session->{'user'}->{'role'};
    if ($user_role && $self->config->{'roles'}->{$user_role}->{'mediator'}) {
        return 1;
    }

    $self->render_not_found;
    return undef;
}

sub list {
    my $self = shift;

    my $company_id = $self->param('company_id');
    return $self->render_not_found unless $company_id;

    my $company = Rplus::Model::Company::Manager->get_objects(query => [ id => $company_id, delete_date => undef ])->[0];
    return $self->render_not_found unless $company;

    my $res = {
        count => 0,
        list => [],
        company => {
            id => $company->id,
            name => $company->name,
        }
    };
    my $mediator_iter = Rplus::Model::Mediator::Manager->get_objects_iterator(query => [ company_id => $company_id, delete_date => undef ], sort_by => 'phone_num');
    while (my $mediator = $mediator_iter->next) {
        push @{$res->{'list'}}, {
            id => $mediator->id,
            name => $mediator->name,
            phone_num => format_phone_num($mediator->phone_num, 'human'),
        };
    }
    $res->{'count'} = @{$res->{'list'}};

    $self->render_json($res);
}

sub add {
    my $self = shift;

    my $company_name = trim(scalar($self->param('company')));
    my $name = trim(scalar($self->param('name')));
    my $phone_num = format_phone_num(scalar($self->param('phone_num')));

    my @errors;
    {
        push @errors, { field => 'company', msg => 'Empty company name' } unless $company_name;
        push @errors, { field => 'name', msg => 'Empty mediator name' } unless $name;
        push @errors, { field => 'phone_num', msg => 'Invalid phone num' } unless $phone_num;
    }
    return $self->render_json({status => 'failed', errors => \@errors}) if @errors;

    my $company = Rplus::Model::Company::Manager->get_objects(query => [ name_lc => lc($company_name), delete_date => undef ])->[0];

    eval {
        my $db = Rplus::DB->new;
        $db->begin_work;

        if (!$company) {
            $company = Rplus::Model::Company->new(name => $company_name, db => $db);
            $company->save;
        }

        my $mediator = Rplus::Model::Mediator->new(company_id => $company->id, name => $name, phone_num => $phone_num, db => $db);
        $mediator->save;
        $mediator->load;

        # Дополнительно, найдем другие телефоны этого посредника
        my $_found_phones = { $phone_num => 0 };
        do {
            for my $x (keys %$_found_phones) {
                next if $_found_phones->{$x};
                my $phones_new = Rplus::DB->new->dbh->selectall_arrayref(qq{
                    SELECT C.contact_phones
                    FROM realty R
                    INNER JOIN clients C ON (C.id = R.seller_id)
                    WHERE R.state IN ('raw', 'work', 'closed_temporary') AND C.contact_phones @> '{$x}'
                }, { Slice => {} });
                for my $row (@$phones_new) {
                    for (@{$row->{'contact_phones'}}) {
                        $_found_phones->{$_} = 0 unless exists $_found_phones->{$_};
                    }
                }
                $_found_phones->{$x} = 1;
            }
        } while (any { $_found_phones->{$_} == 0 } (keys %$_found_phones));

        {
            # Сохраним новые найденные телефоны посредника
            for my $x (@{Rplus::Model::Mediator::Manager->get_objects(query => [ delete_date => undef, phone_num => [ keys %$_found_phones ] ], db => $db)}) {
                $_found_phones->{$x->phone_num} = 2 if exists $_found_phones->{$x->phone_num};
            }
            for my $x (keys %$_found_phones) {
                next if $_found_phones->{$x} == 2;
                Rplus::Model::Mediator->new(company_id => $company->id, name => $name, phone_num => $x, db => $db)->save;
            }
        }

        my $num_rows_updated = Rplus::Object::Realty::Manager->update_objects(
            set => { state => 'closed_mediator' },
            where => [
                state => ['raw', 'work', 'closed_temporary'],
                \("seller_id IN (SELECT C.id FROM clients C WHERE C.contact_phones && '{".join(',', (keys %$_found_phones))."}')"),
            ],
            db => $db,
        );

        $db->commit;

        1;
    } or do {
        if ($@ =~ /\Qmediators_phone_num_uniq_idx\E/) {
            return $self->render_json({status => 'failed', errors => [{ field => 'phone_num', msg => 'Duplicate phone num' }]});
        } else {
            return $self->render_json({status => 'failed', errors => [{ msg => 'An error occurred: '.$@ }]});
        }
    };

    return $self->render_json({
        status => 'success',
        data => {
            company => {
                id => $company->id,
                name => $company->name,
            }
        }
    });
}

sub save {
    my $self = shift;

    my $id = $self->param('id');
    my $name = trim(scalar($self->param('name')));
    my $phone_num = format_phone_num(scalar($self->param('phone_num'))); # Not used

    return $self->render_json({status => 'failed'}) unless $id && $name;

    my $mediator = Rplus::Model::Mediator::Manager->get_objects(query => [ id => $id, delete_date => undef ])->[0];
    return $self->render_json({status => 'failed'}) unless $mediator;

    $mediator->name($name);
    $mediator->save;

    return $self->render_json({status => 'success'});
}

sub delete {
    my $self = shift;

    my $id = $self->param('id');
    return $self->render_json({status => 'failed'}) unless $id;

    my $num_rows_updated = Rplus::Model::Mediator::Manager->update_objects(
        set => { delete_date => \'now()' },
        where => [ id => $id, delete_date => undef ],
    );
    return $self->render_json({status => 'failed'}) unless $num_rows_updated;

    $self->render_json({status => 'success'});
}

1;
