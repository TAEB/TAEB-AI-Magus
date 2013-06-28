package TAEB::AI::Magus::Goal::QuestExperience;
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub met_when { TAEB->level >= 14 }

1;

