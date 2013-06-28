package TAEB::AI::Magus::Goal;
use Moose;

sub met_when { die shift . " must implement met_when" }

1;

