using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
using Bastos.Native.Infrastructure;

namespace Bastos.Native.Models;

public sealed class PerformanceMetric : ObservableObject
{
	private const int HistoryLength = 61;

	private readonly Queue<double> history = new Queue<double>();

	private string displayValue = "Initialisation…";

	private string detail = "Lecture des compteurs Windows";

	private string secondary = "";

	private double percent;

	private PointCollection chartPoints = new PointCollection();

	public string Title { get; }

	public string Accent { get; }

	public string Value
	{
		get
		{
			return displayValue;
		}
		private set
		{
			SetProperty(ref displayValue, value, "Value");
		}
	}

	public string Detail
	{
		get
		{
			return detail;
		}
		private set
		{
			SetProperty(ref detail, value, "Detail");
		}
	}

	public string Secondary
	{
		get
		{
			return secondary;
		}
		private set
		{
			SetProperty(ref secondary, value, "Secondary");
		}
	}

	public double Percent
	{
		get
		{
			return percent;
		}
		private set
		{
			SetProperty(ref percent, value, "Percent");
		}
	}

	public PointCollection ChartPoints
	{
		get
		{
			return chartPoints;
		}
		private set
		{
			SetProperty(ref chartPoints, value, "ChartPoints");
		}
	}

	public PerformanceMetric(string title, string accent)
	{
		Title = title;
		Accent = accent;
		for (int i = 0; i < 61; i++)
		{
			history.Enqueue(0.0);
		}
		RebuildChart();
	}

	public void Update(double newPercent, string newValue, string newDetail, string newSecondary)
	{
		Percent = Math.Clamp(double.IsFinite(newPercent) ? newPercent : 0.0, 0.0, 100.0);
		Value = newValue;
		Detail = newDetail;
		Secondary = newSecondary;
		history.Enqueue(Percent);
		while (history.Count > 61)
		{
			history.Dequeue();
		}
		RebuildChart();
	}

	private void RebuildChart()
	{
		double num = 300.0 / (double)Math.Max(1, 60);
		PointCollection pointCollection = new PointCollection(61);
		int num2 = 0;
		foreach (double item in history)
		{
			pointCollection.Add(new Point((double)num2 * num, 72.0 - item / 100.0 * 68.0 - 2.0));
			num2++;
		}
		pointCollection.Freeze();
		ChartPoints = pointCollection;
	}
}
