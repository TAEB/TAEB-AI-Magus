package TAEB::AI::Magus::QueueManager;
use Moose;

use TAEB::Util 'weaken';

has magus => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
);

has queued_actions => (
    traits  => ['Array'],
    isa     => 'ArrayRef[TAEB::Action|CodeRef]',
    default => sub { [] },
    handles => {
        enqueue_actions    => 'push',
        dequeue_action     => 'shift',
        has_queued_actions => 'count',
    },
);

has temporary_subscriptions => (
    traits  => ['Array'],
    isa     => 'ArrayRef',
    lazy    => 1,
    default => sub { [] },
    clearer =>'clear_temporary_subscriptions',
    handles => {
        register_temporary_subscription => 'push',
    },
);

has currently => (
    is      => 'rw',
    isa     => 'Str',
    clearer => 'clear_currently',
);

around currently => sub {
    my $orig = shift;
    my $self = shift;

    return $self->$orig(@_) if @_;
    return $self->$orig . ' [queue]';
};

sub next_queued_action {
    my $self = shift;

    if (!$self->has_queued_actions) {
        $self->clear_temporary_subscriptions;
        $self->clear_currently;
        return;
    }

    my $next = $self->dequeue_action;

    if (blessed($next) && $next->isa('TAEB::Action')) {
        return $next;
    }
    elsif (ref($next) eq 'CODE') {
        my $magus = $self->magus;
        weaken($magus);

        my $wrapper = sub {
            my ($name, $crap, @args) = @_;
            $next->($magus, $name, @args);
        };

        TAEB->publisher->subscribe($wrapper);
        $self->register_temporary_subscription($wrapper);

        # now we registered this subscriber, carry on to the next action
        return $self->next_queued_action;
    }
    else {
        confess "$next is not a TAEB::Action or a coderef...?";
    }
}

sub unsubscribe_temporary_subscriptions {
    my $self = shift;

    for my $subscription ($self->temporary_subscriptions) {
        TAEB->publisher->unsubscribe($subscription);
    }

    $self->clear_temporary_subscriptions;
}

1;

