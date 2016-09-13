package RplusMgmt::Controller::API::Statistics;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Account::Manager;
use Rplus::Model::Realty::Manager;
use Rplus::Model::MediatorCompany::Manager;
use Rplus::Model::Mediator::Manager;
use Rplus::Model::SubscriptionRealty::Manager;
use Rplus::Model::Option::Manager;
use Rplus::Model::DictTaskType::Manager;
use Rplus::Model::RealtyState::Manager;

use Rplus::Util::PhoneNum;
use Rplus::Util::Query;
use Rplus::Util::Realty;
use Rplus::Util::Mediator qw(add_mediator);
use Rplus::Util::Task;
use Rplus::Util::Geo;


use File::Path qw(make_path);
use POSIX qw(strftime);

use Data::Dumper;
use JSON;
use Mojo::Collection;
use Time::Piece;
use DateTime;


no warnings 'experimental::smartmatch';

sub get_obj_price_data {
    my $self = shift;

    my $obj_id = $self->param('id');

    my $res = {
      list => [],
      like_list => [],
      task_list => []
    };

    # текущая цена
    my $obj = Rplus::Model::Realty::Manager->get_objects(query => [
        id => $obj_id,
    ])->[0];

    my $log_iter = Rplus::Model::HistoryRecord::Manager->get_objects_iterator(query => [
        object_type => 'realty',
        type => ['update', 'update_media'],
        object_id => $obj_id,
      ],
      sort_by => 'date'
    );

    # стартовая цена
    my $log_first = Rplus::Model::HistoryRecord::Manager->get_objects(query => [
        object_type => 'realty',
        type => ['add', 'add_media'],
        object_id => $obj_id,
    ])->[0];

    if ($log_first) {
        my $x = {
            mark => 's',
            date => $log_first->date,
            price_pair => [undef, from_json($log_first->metadata)->{owner_price}]
        };
        push @{$res->{list}}, $x;
    }

    while (my $rec = $log_iter->next) {
        my $x = {
            date => $rec->date,
            price_pair => from_json($rec->metadata)->{owner_price},
        };
        push @{$res->{list}}, $x;
    }

    if ($obj) {
        my $x = {
            mark => 'e',
            date => DateTime->now(time_zone=>'local')->iso8601(),
            price_pair => [$obj->owner_price, undef],
        };
        push @{$res->{list}}, $x;
    }

    my $t = Rplus::DB->new_or_cached->dbh->selectall_hashref(
        q{
        SELECT d.date, count(hr.id) FROM (
            SELECT to_char(date_trunc('day', (current_date - offs)), 'YYYY-MM-DD')
            AS date
            FROM generate_series(0, 7, 1)
            AS offs
            ) d
        LEFT OUTER JOIN (
            SELECT date, id
            FROM history_records
            WHERE type = 'like_it' AND object_id = } . $obj_id . q{
            ) hr
        ON (d.date = to_char(date_trunc('day', hr.date), 'YYYY-MM-DD'))
        GROUP BY d.date}, 'date');

    for (sort keys %{$t}) {
        my $rec = $t->{$_};
        my $x = {
            date => $rec->{date},
            count => $rec->{count},
        };
        push @{$res->{like_list}}, $x;
    }

    $t = Rplus::DB->new_or_cached->dbh->selectall_hashref(
        q{
          SELECT d.date, count(tsk.id) FROM (
              SELECT to_char(date_trunc('day', (current_date - offs)), 'YYYY-MM-DD')
              AS date
              FROM generate_series(0, 7, 1)
              AS offs
              ) d
          LEFT OUTER JOIN (
              SELECT completion_date, id
              FROM tasks
              WHERE task_type_id = 64 AND completion_date IS NOT NULL AND realty_id = } . $obj_id . q{
              ) tsk
          ON (d.date = to_char(date_trunc('day', tsk.completion_date), 'YYYY-MM-DD'))
          GROUP BY d.date}, 'date');

    for (sort keys %{$t}) {
        my $rec = $t->{$_};
        my $x = {
            date => $rec->{date},
            count => $rec->{count},
        };
        push @{$res->{task_list}}, $x;
    }

    return $self->render(json => $res);
}

sub get_price_data {
    my $self = shift;

    return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(realty => 'read');

    # Input validation

    # Input params
    my $q = $self->param_n('q');
    my $offer_type_code = $self->param('offer_type_code') || 'any';
    my $rent_type = $self->param('rent_type') || 'any';

    my $from_date = $self->param('from_date');
    my $to_date = $self->param('to_date');

    my $object_count = $self->param("object_count") || 10000;

    my $rq_id = $self->param("rq_id") || 42;
    my $acc_id = $self->session('account')->{id};


    # "where" query
    my @query;
    my $near;
    {
        if ($q =~ s/(рядом )(.+)/ /i) {
            $near = $2;
        }

        if ($from_date) {
          push @query, add_date => {gt => $from_date};
        }

        if ($to_date) {
          push @query, add_date => {le => $to_date};
        }

        if ($offer_type_code ne 'any') {
            push @query, offer_type_code => $offer_type_code;
        }

        if ($offer_type_code eq 'rent' && $rent_type ne 'any') {
            push @query, rent_type => $rent_type;
        }
    }

    # Recognize phone numbers from query
    my @owner_phones;
    if ($q) {
        for my $x (split /[ .,]/, $q) {
            if ($x =~ /^\s*[0-9-]{6,}\s*$/) {
                if (my $phone_num = $self->parse_phone_num($x)) {
                    push @owner_phones, $phone_num;
                    $q =~ s/$x//;
                }
            }
        }
        push @query, \("t1.owner_phones && '{".join(',', map { '"'.$_.'"' } @owner_phones)."}'") if @owner_phones;
    }

    push @query, or => [account_id => undef, account_id => $acc_id];
    push @query, \("NOT hidden_for && '{".$acc_id."}'");

    # Parse query
    push @query, Rplus::Util::Query::parse($q, $self);

    if ($near) {
        my $points = get_near_filter($near);

        my $max_points = 100;
        if (scalar @{$points}) {
            my @near_query = ();
            foreach (@{$points}) {
                if ((scalar @near_query) == $max_points) {last};
                push @near_query, \("postgis.st_distance(t1.geocoords, postgis.ST_GeographyFromText('SRID=4326;POINT(" . $_->{lon} . " " . $_->{lat} . ")'), true) < 500");
            }

            push @query, or => \@near_query;
        }
    }


    my $res = {
      list => []
    };

    # Fetch realty objects
    my $realty_iter = Rplus::Model::Realty::Manager->get_objects_iterator (
        select => ['realty.add_date', 'realty.price'],
        query => [
            @query,
            delete_date => undef,
        ],
        page => 1,
        per_page => $object_count,
    );

    while (my $realty = $realty_iter->next) {
        my $x = {
            add_date => $realty->add_date,
            cost => $realty->price * 1000,
        };
        push @{$res->{list}}, $x;
    }

    return $self->render(json => $res);
}

sub get_agent_objects_data {
  my $self = shift;

  my $agent_id = $self->param('agent_id');
  my $offer_type_code = $self->param('offer_type_code') || 'any';
  my $acc_id = $self->session('account')->{id};

  my @query;
  push @query, agent_id => $agent_id;
  push @query, offer_type_code => $offer_type_code;
  push @query, or => [account_id => undef, account_id => $acc_id];
  push @query, \("NOT hidden_for && '{".$acc_id."}'");

  my $res = {
    list => []
  };

  for my $x (@{Rplus::Model::RealtyState::Manager->get_objects(sort_by => 'sort_idx')}) {
    my $state_count = Rplus::Model::Realty::Manager->get_objects_count (
        query => [
          @query,
          state_code => $x->code,
          delete_date => undef,
        ],
    );
    my $x = {
        state_code => $x->name,
        count => $state_count,
    };
    push @{$res->{list}}, $x;
  }

  return $self->render(json => $res);
}

sub get_agent_tasks_data {
  my $self = shift;

  my $agent_id = $self->param('agent_id');

  my $from_date = $self->param('from_date');
  my $to_date = $self->param('to_date');

  my @assigned_query;
  my @done_query;

  if ($from_date) {
    push @assigned_query, start_date => {gt => $from_date};

    push @done_query, start_date => {gt => $from_date};
  }

  if ($to_date) {
    push @assigned_query, start_date => {le => $to_date};

    push @done_query, start_date => {le => $to_date};
    push @done_query, completion_date => {le => $to_date};
  } else {
    push @done_query, status => 'done';
  }

  my $res = {
    list => []
  };

  for my $x (@{Rplus::Model::DictTaskType::Manager->get_objects(query => [delete_date => undef], sort_by => 'id')}) {

    my $assigned_count = Rplus::Model::Task::Manager->get_objects_count (
      query => [
        @assigned_query,
        task_type_id => $x->id,
        assigned_user_id => $agent_id,
        delete_date => undef,
      ],
    );

    my $done_count = Rplus::Model::Task::Manager->get_objects_count (
      query => [
        @done_query,
        task_type_id => $x->id,
        assigned_user_id => $agent_id,
        delete_date => undef,
      ],
    );

    my $x = {
        task_name => $x->name,
        assigned_count => $assigned_count,
        done_count => $done_count,
    };

    push @{$res->{list}}, $x;
  }

  return $self->render(json => $res);
}

1;
