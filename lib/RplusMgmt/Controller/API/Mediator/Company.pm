package RplusMgmt::Controller::API::Mediator::Company;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::MediatorCompany;
use Rplus::Model::MediatorCompany::Manager;
use Rplus::Model::Mediator;
use Rplus::Model::Mediator::Manager;

use Rplus::DB;
use Mojo::Util qw(trim);

sub auth {
    my $self = shift;

    my $user_role = $self->session->{'user'}->{'role'};
    if ($user_role && $self->config->{'roles'}->{$user_role}->{'configuration'}->{'mediators'}) {
        return 1;
    }

    $self->render_not_found;
    return undef;
}

sub list {
    my $self = shift;

    my $filter = $self->param('filter');

    my ($name_filter, $phone_filter);
    if ($filter) {
        $filter = trim $filter;
        $filter =~ s/([%_])/\\$1/g;
        $name_filter = lc $filter;
        if ($filter =~ /^\+?\d{1,11}$/) {
            if ($filter =~ s/^8(.*)$/$1/) {} elsif ($filter =~ s/^\+7(.*)$/$1/) {}
            $phone_filter = $filter;
        }
    }

    # Используется для _быстрого_ подсчета количества телефонов в компании
    my $db = Rplus::DB->new_or_cached;
    my $mediators_count = $db->dbh->selectall_hashref(q{
        SELECT MC.id, count(M.id) mediators_count
        FROM mediator_companies MC
        LEFT JOIN mediators M ON (M.company_id = MC.id AND M.delete_date IS NULL)
        WHERE MC.delete_date IS NULL
        GROUP BY MC.id
    }, 'id');

    my $res = {
        count => 0,
        list => [],
    };
    my $company_iter = Rplus::Model::MediatorCompany::Manager->get_objects_iterator(
        query => [
            delete_date => undef,
            ($name_filter ? (
                or => [
                    [\'lower(name) LIKE ?' => lc($filter).'%'],
                    ($phone_filter ? (
                        [\'t1.id IN (SELECT M.company_id FROM mediators M WHERE M.delete_date IS NULL AND M.phone_num LIKE ?)' => '%'.$phone_filter.'%']
                    ) : ()),
                ]
            ) : ()),
        ],
        sort_by => 'lower(name)',
    );
    while (my $company = $company_iter->next) {
        push @{$res->{'list'}}, {
            id => $company->id,
            name => $company->name,
            mediators_count => $mediators_count->{$company->id}->{'mediators_count'},
        };
        $res->{'count'}++;
    }

    return $self->render(json => $res);
}

sub save {
    my $self = shift;

    my $id = $self->param('id');
    my $name = trim(scalar $self->param('name')) || undef;

    my $company = Rplus::Model::MediatorCompany::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render_not_found unless $company;

    return $self->render(json => {status => 'failed', errors => [{field => 'name', msg => 'Empty company name'}]}) unless $name;

    # Попробуем найти компанию с таким же именем
    my $company_dest = Rplus::Model::MediatorCompany::Manager->get_objects(query => [[\'lower(t1.name) LIKE ?' => lc($name)], delete_date => undef])->[0];
    if ($company_dest && $company->id != $company_dest->id) {
        # Выполним перенос
        my $db = Rplus::DB->new_or_cached;
        $db->begin_work;
        Rplus::Model::Mediator::Manager->update_objects(
            set => {company_id => $company_dest->id},
            where => [company_id => $company->id, delete_date => undef],
            db => $db,
        );
        Rplus::Model::MediatorCompany::Manager->update_objects(
            set => {delete_date => \'now()'},
            where => [id => $company->id],
            db => $db,
        );
        $db->commit;
        $company = $company_dest;
    } else {
        # Выполним сохранение
        eval {
            $company->name($name);
            $company->save;
            1;
        } or do {
            if ($@ =~ /\Qname_uniq_idx\E/) {
                return $self->render(json => {status => 'failed', errors => [{field => 'name', msg => 'Duplicate company name'}]});
            } else {
                return $self->render(json => {status => 'failed', errors => [{msg => 'An error occurred'}]});
            }
        };
    }

    return $self->render(json => {status => 'success', data => {id => $company->id, name => $company->name}});
}

sub delete {
    my $self = shift;

    my $id = $self->param('id');

    # Удалим компанию
    my $num_rows_updated = Rplus::Model::MediatorCompany::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [id => $id, delete_date => undef],
    );
    return $self->render(json => {status => 'failed'}) unless $num_rows_updated;

    # Теперь удалим номера телефонов данной компании
    my $num_rows_updated2 = Rplus::Model::Mediator::Manager->update_objects(
        set => {delete_date => \'now()'},
        where => [company_id => $id, delete_date => undef],
    );

    return $self->render(json => {status => 'success'});
}

1;
